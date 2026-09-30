# frozen_string_literal: true

require "socket"

module Cosmo
  module API
    class Busy
      TTL = 70
      LIMIT = 25
      HEARTBEAT = 30
      BUCKET = "cosmo_jobs_busy"

      def self.instance
        @instance ||= new
      end

      def initialize
        @messages = {}
        @kv = KV.new(BUCKET, { ttl: TTL })
      end

      def with(message)
        add(message)
        yield
      ensure
        delete(message)
      end

      def add(message)
        @thread ||= Thread.new { heartbeat_loop }
        meta = message.metadata
        seq = meta.sequence.stream
        value = Utils::Json.dump({ data: message.data, stream: meta.stream, worker: worker_id,
                                   started_at: Time.now.to_i, delivery: meta.num_delivered })
        @messages[seq] = value
        @kv.set(seq, value)
      end

      def delete(message)
        seq = message.metadata.sequence.stream
        @messages.delete(seq)
        @kv.purge(seq)
      end

      def list(page: nil, limit: LIMIT)
        offset = ([page.to_i, 1].max - 1) * limit
        @kv.entries(limit:, offset:).filter_map { Utils::Json.parse(_1.last) }
           .map { _1.merge(data: Utils::Json.parse(_1[:data])) }
      end

      def size
        @kv.size
      end

      private

      def heartbeat_loop
        loop do
          sleep(HEARTBEAT)
          @messages.dup.each { |seq, value| @kv.set(seq, value) rescue StandardError }
        rescue StandardError => e
          Logger.debug "Busy heartbeat error: #{e.class} #{e.message}"
        end
      end

      def worker_id
        @worker_id ||= "#{Socket.gethostname}-#{Process.pid}"
      end
    end
  end
end
