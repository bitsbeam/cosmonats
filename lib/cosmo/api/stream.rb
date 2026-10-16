# frozen_string_literal: true

require "cosmo/api/job"

module Cosmo
  module API
    class Stream
      LIMIT = 20

      include Enumerable

      # @return [Array<Stream>] every stream, each answering #info from this one listing
      def self.all
        client.list_streams.map { new(_1.config.name, _1) }
      end

      # @return [Array<Stream>] the job streams, each answering #info from this one listing
      def self.jobs
        client.list_streams.select { _1.config.metadata&.[](:"_cosmo.type") == "jobs" }
              .reject { %w[scheduled dead].include?(_1.config.name) }
              .map { new(_1.config.name, _1) }
      end

      def self.client
        @client ||= Client.instance
      end

      attr_reader :name

      # @param name [String]
      # @param info [NATS::JetStream::API::StreamInfo, nil] the stream's info from a listing, kept instead of fetched
      def initialize(name, info = nil)
        @name = name
        @info = info
      end

      # @return [Hash] the stream's +:state+ and +:config+ as JetStream reports them, from the listing the stream
      #   came from or else fetched fresh on every call
      def info
        info = @info || client.stream_info(name)
        { state: info.state, config: info.config }
      end

      def total
        state, config = info.values_at(:state, :config)
        messages = state.messages.to_i
        return messages unless Array(config.subjects).any? { _1.start_with?(Cron::Entry::SUBJECT_PREFIX) }

        cron_count = client.cron_subjects_in_stream(name, "#{Cron::Entry::SUBJECT_PREFIX}.>").size
        [messages - cron_count, 0].max
      rescue NATS::Error
        0
      end
      alias size total

      def retries
        consumers.sum { _1["num_redelivered"].to_i }
      end

      # @return [Array<Hash>] the stream's consumers as JetStream reports them, with their config and delivery state
      def consumers
        client.list_consumers(name)
      rescue NATS::Error
        []
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

      # @return [Boolean] false when the server doesn't answer in time
      def paused?
        info[:config].metadata&.[](:"_cosmo.paused") == "true"
      rescue NATS::IO::Timeout
        false
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
