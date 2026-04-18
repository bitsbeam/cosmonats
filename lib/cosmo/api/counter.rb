# frozen_string_literal: true

module Cosmo
  module API
    class Counter
      STREAM_NAME = "cosmostats"

      def self.instance
        @instance ||= new("jobs")
      end

      def initialize(namespace)
        @namespace = namespace
      end

      def with
        result = yield
        increment(:processed) if result == true
        increment(:failed) if result == false
      rescue Exception # rubocop:disable Lint/RescueException
        increment(:failed)
      end

      def increment(key, by: 1)
        publish(key, "+#{by}")
      end
      alias incr increment

      def decrement(key, by: 1)
        publish(key, "-#{by}")
      end
      alias decr decrement

      def reset(key)
        client.purge(STREAM_NAME, subject(key))
      end

      def get(key)
        raw = client.get_message(STREAM_NAME, direct: true, subject: subject(key))
        Utils::Json.parse(raw.data, default: { "val" => 0 })[:val].to_i
      rescue NATS::JetStream::Error::NotFound, NATS::JetStream::Error::ServiceUnavailable
        0
      end

      private

      def publish(key, value)
        rescued = nil

        begin
          client.publish(subject(key), "", header: { "Nats-Incr" => value }).val.to_i
        rescue NATS::JetStream::Error::NoStreamResponse
          raise if rescued

          rescued = true
          client.create_stream(STREAM_NAME, subjects: ["#{STREAM_NAME}.>"], allow_msg_counter: true, allow_direct: true, description: "Cosmo statistics")
          retry
        end
      end

      def subject(key)
        "#{STREAM_NAME}.#{@namespace}.#{key}"
      end

      def client
        @client ||= Client.instance
      end
    end
  end
end
