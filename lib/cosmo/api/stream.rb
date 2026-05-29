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
        info[:state].messages.to_i
      rescue NATS::Error
        0
      end
      alias size total

      def retries
        client.list_consumers(name).sum { _1["num_redelivered"].to_i }
      end

      def each
        return if total.zero?

        state = info[:state]
        current = @offset || state.first_seq.to_i
        last = state.last_seq.to_i

        loop do
          break if current > last

          job = message(current)
          current += 1
          next unless job

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
        Job.new(name, client.get_message(name, seq: seq, direct: true))
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

      def client
        self.class.client
      end
    end
  end
end
