# frozen_string_literal: true

require "securerandom"
require "cosmo/api/cron/entry"

module Cosmo
  module API
    # Web-facing API for cron schedules. Single interface for all cron NATS operations.
    #
    # Derives the schedule list entirely from NATS.
    # Whatever is deployed in NATS is exactly what appears in the UI.
    #
    # Every schedule template lives in the +scheduled+ stream, at a subject matching
    # +cosmo.cron.<target stream>.>+. NATS fires a template by publishing its body to
    # +Nats-Schedule-Target+, which has to be a subject the storing stream covers, so a firing
    # lands back in +scheduled+ and the job processor's scheduler dispatches it to the stream
    # that runs it. That confines message scheduling - and the +discard: old+ NATS demands
    # wherever scheduling is enabled - to a single stream.
    class Cron
      STREAM = ::Cosmo::Job::StreamFilter::SCHEDULED.to_s

      def self.instance
        @instance ||= new
      end

      # @return [Array<Hash>] every cron schedule currently deployed in NATS
      def all
        schedules
      rescue StandardError
        []
      end

      # Publish (or replace) a schedule message in NATS.
      # @return [Hash, nil] the persisted schedule as a hash, or nil on failure
      def upsert!(class_name: nil, stream: nil, schedule: nil, args: [], timezone: nil, name: nil)
        e = Entry.new(class_name: class_name, stream: stream, expression: schedule,
                      args: args, timezone: timezone, name: name)
        client.publish(e.schedule_subject, e.job_payload, stream: STREAM, header: e.schedule_headers)
        build_from_nats(e.schedule_subject)
      end

      # Purge the schedule message from NATS (stops future firings).
      # @param subject [String]
      def delete!(subject)
        client.purge(STREAM, subject)
      rescue NATS::JetStream::Error::NotFound, NATS::IO::Timeout
        nil
      end

      # Dispatch the job immediately to the target stream, bypassing the timer.
      # @param schedule_subject [String] e.g. "cosmo.cron.default.report_job.daily"
      def run_now!(schedule_subject) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        msg = client.get_message(STREAM, subject: schedule_subject)
        return unless msg

        headers = msg.headers || {}
        body = Utils::Json.parse(msg.data) || {}
        target = headers["X-Subject"]
        return unless target && body[:class]

        payload = Utils::Json.dump({
                                     jid: SecureRandom.hex(12),
                                     class: body[:class],
                                     args: body[:args] || [],
                                     retry: body[:retry] || Job::Data.default_retry,
                                     dead: body[:dead].nil? ? Job::Data::DEFAULTS[:dead] : body[:dead]
                                   })
        client.publish(target, payload, stream: headers["X-Stream"])
      rescue NATS::JetStream::Error::NotFound
        nil
      end

      private

      def client
        @client ||= Client.instance
      end

      def schedules
        subjects = client.cron_subjects_in_stream(STREAM, "#{Entry::SUBJECT_PREFIX}.>")
        subjects.filter_map { |subj| build_from_nats(subj) }
      end

      def build_from_nats(subject)
        msg = client.get_message(STREAM, subject: subject)
        return unless msg

        headers = msg.headers || {}
        body = Utils::Json.parse(msg.data) || {}

        {
          class: body[:class],
          stream: headers["X-Stream"],
          schedule: headers["Nats-Schedule"],
          timezone: headers["Nats-Schedule-Time-Zone"],
          args: body[:args] || [],
          name: name_from_subject(subject),
          schedule_subject: subject,
          dispatch_subject: headers["X-Subject"],
          registry_key: subject.split(".").drop(2).join("/")
        }
      rescue StandardError
        nil
      end

      # "cosmo.cron.default.report_job"         → nil
      # "cosmo.cron.default.report_job.monthly" → "monthly"
      def name_from_subject(subject)
        parts = subject.to_s.split(".")
        parts.length > 4 ? parts.drop(4).join(".") : nil
      end
    end
  end
end
