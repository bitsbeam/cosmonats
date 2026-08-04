# frozen_string_literal: true

module Cosmo
  module API
    class Counter
      STREAM_NAME = "_cosmostats"

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

      def increment(key, by: 1, msg_id: nil)
        publish(key, "+#{by}", msg_id: msg_id)
      end
      alias incr increment

      def decrement(key, by: 1, msg_id: nil)
        publish(key, "-#{by}", msg_id: msg_id)
      end
      alias decr decrement

      def reset(key)
        client.purge(STREAM_NAME, subject(key))
      end
      alias purge reset

      def get(key)
        raw = client.get_message(STREAM_NAME, direct: true, subject: subject(key))
        Utils::Json.parse(raw.data, default: { "val" => 0 })[:val].to_i
      rescue NATS::JetStream::Error::NotFound, NATS::JetStream::Error::ServiceUnavailable, NATS::IO::Timeout
        0
      end

      private

      # @param msg_id [String, nil] when given, sent as Nats-Msg-Id so a redelivered
      #   caller (e.g. a job whose ack was lost and retried) collapses onto the
      #   stream's duplicate_window instead of double-applying the +/- delta.
      # @return [Integer, nil] the resulting counter value, or +nil+ when this exact
      #   +msg_id+ was already applied (a deduped publish's PubAck carries no +val+
      #   at all -- coercing that to 0 would look identical to "counter is now 0",
      #   so callers must treat +nil+ as "no new information" rather than a real value).
      def publish(key, value, msg_id: nil)
        rescued = nil
        headers = { "Nats-Incr" => value }
        headers["Nats-Msg-Id"] = msg_id if msg_id

        begin
          ack = client.publish(subject(key), "", header: headers)
          ack.val.to_i unless ack.duplicate
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
