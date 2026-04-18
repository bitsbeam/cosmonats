# frozen_string_literal: true

require "socket"

module Cosmo
  module API
    class Busy
      TTL = 70
      HEARTBEAT = 30
      BUCKET = "cosmostats"

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
        seq = message.metadata.sequence.stream
        value = Utils::Json.dump({ data: message.data, stream: message.metadata.stream, worker: worker_id, started_at: Time.now.to_i })
        @messages[seq] = value
        @kv.set(seq, value)
      end

      def delete(message)
        seq = message.metadata.sequence.stream
        @messages.delete(seq)
        @kv.purge(seq)
      end

      def list(limit: 25)
        @kv.keys(limit:).filter_map { Utils::Json.parse(@kv.get(_1)) }.map { _1.merge(data: Utils::Json.parse(_1[:data])) }
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
