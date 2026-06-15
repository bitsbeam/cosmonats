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
    # Schedule templates live in the same job stream they target (e.g. +default+),
    # stored at subjects matching +cosmo.cron.<stream>.>+. NATS 2.14 fires each
    # template by publishing the body to +Nats-Schedule-Target+ as a regular
    # JetStream message that accumulates alongside pending jobs.
    class Cron
      def self.instance
        @instance ||= new
      end

      # @return [Array<Hash>] every cron schedule currently deployed in NATS
      def all
        Stream.jobs.flat_map { |s| schedules_from_stream(s.name) }
      rescue StandardError
        []
      end

      # Publish (or replace) a schedule message in NATS.
      # @return [Hash, nil] the persisted schedule as a hash, or nil on failure
      def upsert!(class_name: nil, stream: nil, schedule: nil, args: [], timezone: nil, name: nil)
        e = Entry.new(class_name: class_name, stream: stream, expression: schedule,
                      args: args, timezone: timezone, name: name)
        headers = {
          "Nats-Schedule" => e.expression,
          "Nats-Schedule-Target" => e.target_subject
        }
        headers["Nats-Schedule-Time-Zone"] = e.timezone if e.timezone
        client.publish(e.schedule_subject, e.job_payload, stream: e.stream, header: headers)
        build_from_nats(e.stream, e.schedule_subject)
      end

      # Purge the schedule message from NATS (stops future firings).
      # @param subject [String]
      def delete!(subject)
        stream_name = subject.to_s.split(".")[2]
        client.purge(stream_name, subject)
      rescue NATS::JetStream::Error::NotFound, NATS::IO::Timeout
        nil
      end

      # Dispatch the job immediately to the target stream, bypassing the timer.
      # @param schedule_subject [String] e.g. "cosmo.cron.default.report_job.daily"
      def run_now!(schedule_subject) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        stream_name = schedule_subject.to_s.split(".")[2]
        msg = client.get_message(stream_name, subject: schedule_subject)
        return unless msg

        headers = msg.headers || {}
        body = Utils::Json.parse(msg.data) || {}
        target = headers["Nats-Schedule-Target"]
        return unless target && body[:class]

        payload = Utils::Json.dump({
                                     jid: SecureRandom.hex(12),
                                     class: body[:class],
                                     args: body[:args] || [],
                                     retry: body[:retry] || Job::Data::DEFAULTS[:retry],
                                     dead: body[:dead].nil? ? Job::Data::DEFAULTS[:dead] : body[:dead]
                                   })
        client.publish(target, payload, stream: stream_name)
      rescue NATS::JetStream::Error::NotFound
        nil
      end

      private

      def client
        @client ||= Client.instance
      end

      def schedules_from_stream(stream_name)
        filter = "#{Entry::SUBJECT_PREFIX}.#{stream_name}.>"
        subjects = client.cron_subjects_in_stream(stream_name, filter)
        subjects.filter_map { |subj| build_from_nats(stream_name, subj) }
      end

      def build_from_nats(stream_name, subject)
        msg = client.get_message(stream_name, subject: subject)
        return unless msg

        headers = msg.headers || {}
        body = Utils::Json.parse(msg.data) || {}

        {
          class: body[:class],
          stream: stream_name,
          schedule: headers["Nats-Schedule"],
          timezone: headers["Nats-Schedule-Time-Zone"],
          args: body[:args] || [],
          name: name_from_subject(subject),
          schedule_subject: subject,
          target_subject: headers["Nats-Schedule-Target"],
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
