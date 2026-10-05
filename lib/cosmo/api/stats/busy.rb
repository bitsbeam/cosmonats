# frozen_string_literal: true

require "socket"

module Cosmo
  module API
    module Stats
      # Jobs being executed right now, one entry per in-flight message, across all workers.
      class Busy < Registry
        TTL = 70
        HEARTBEAT = 30
        BUCKET = "cosmo_jobs_busy"

        def initialize
          super
          @messages = {}
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
          entry = { data: message.data, stream: meta.stream, worker: worker_id,
                    started_at: Time.now.to_i, delivery: meta.num_delivered }
          @messages[seq] = entry
          put(seq, entry)
        end

        def delete(message)
          seq = message.metadata.sequence.stream
          @messages.delete(seq)
          remove(seq)
        end

        def list(...)
          super.map { _1.merge(data: Utils::Json.parse(_1[:data])) }
        end

        private

        def heartbeat_loop
          loop do
            sleep(HEARTBEAT)
            @messages.dup.each { |seq, entry| put(seq, entry) rescue StandardError }
          rescue StandardError => e
            Logger.debug "Busy heartbeat error: #{e.class} #{e.message}"
          end
        end

        def worker_id
          @worker_id ||= "#{Socket.gethostname}-#{::Process.pid}"
        end
      end
    end
  end
end
