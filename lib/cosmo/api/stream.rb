# frozen_string_literal: true

require "cosmo/api/job"

module Cosmo
  module API
    class Stream
      LIMIT = 20

      include Enumerable

      def self.all
        client.list_streams.map { new(_1.dig("config", "name")) }
      end

      def self.jobs
        client.list_streams.select { _1.dig("config", "metadata", "_cosmo.type") == "jobs" }
                           .reject { %w[scheduled dead].include?(_1.dig("config", "name")) }
                           .map { new(_1.dig("config", "name")) }
      end

      def self.client
        @client ||= Client.instance
      end

      attr_reader :name

      def initialize(name)
        @name = name
      end

      def info
        info = client.stream_info(name)
        { state: info.state, config: info.config }
      end

      def total
        all_msgs = info[:state].messages.to_i
        cron_count = Client.instance.cron_subjects_in_stream(name, "#{Cron::Entry::SUBJECT_PREFIX}.#{name}.>").size
        [all_msgs - cron_count, 0].max
      rescue NATS::Error
        0
      end
      alias size total

      def retries
        client.list_consumers(name).sum { _1["num_redelivered"].to_i }
      end

      def each
        return if total.zero?

        candidates = {}
        current, last, subjects = scan_range

        loop do
          break if current > last

          subject, job = next_candidate(subjects, candidates, current)
          break unless job

          candidates.delete(subject)
          current = job.seq.to_i + 1

          yield job
        end
      end

      def offset(value)
        @offset = value.to_i
        self
      end

      def messages(page: nil, limit: nil)
        jobs = []
        limit = (limit || LIMIT).to_i
        state = info[:state]
        start = state.first_seq.to_i
        start += (page.to_i - 1) * limit if page

        offset(start).each do |message|
          jobs << message
          break if jobs.size >= limit
        end

        jobs
      end

      def message(seq)
        job = Job.new(name, client.get_message(name, seq: seq, direct: true))
        return if job.subject.to_s.start_with?(Cron::Entry::SUBJECT_PREFIX)

        job
      rescue NATS::JetStream::Error::NotFound
        # nop, acked/nacked
      end

      def retry(seq)
        job = message(seq)
        return unless job

        client.publish(job.x_subject, job.message.data)
        delete(seq)
      end

      def delete(seq)
        client.delete_message(name, seq)
      end

      def pause!
        client.pause_stream(name)
      end

      def unpause!
        client.unpause_stream(name)
      end

      def paused?
        client.stream_paused?(name)
      end

      private

      def scan_range
        data = info
        state = data[:state]
        current = @offset || state.first_seq.to_i
        subjects = Array(data[:config].subjects).reject { _1.start_with?(Cron::Entry::SUBJECT_PREFIX) }
        [current, state.last_seq.to_i, subjects]
      end

      # Lowest-seq message at or after current across all job subject filters,
      # caching each subject's next candidate so it isn't re-queried every step.
      def next_candidate(subjects, candidates, current)
        subjects.each do |subject|
          next if candidates.key?(subject)

          candidates[subject] = next_message(subject, current)
        end

        candidates.compact.min_by { |_, msg| msg.seq.to_i }
      end

      # Jump straight to the next message on the subject after seq, skipping any acked/deleted gaps
      def next_message(subject, seq)
        Job.new(name, client.get_message(name, next: true, seq: seq, subject: subject, direct: true))
      rescue NATS::JetStream::Error::NotFound
        nil
      end

      def client
        self.class.client
      end
    end
  end
end
