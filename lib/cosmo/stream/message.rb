# frozen_string_literal: true

require "forwardable"

module Cosmo
  module Stream
    class Message
      extend Forwardable

      delegate %i[subject reply header metadata ack nak term in_progress] => :@msg
      delegate %i[timestamp num_delivered num_pending] => :metadata
      alias nack nak

      # @param msg [NATS::Msg]
      # @param serializer [#deserialize, nil] defaults to {Serializer}
      def initialize(msg, serializer: nil)
        @msg = msg
        @serializer = serializer || Serializer
      end

      # @return [Object] the deserialized payload
      def data
        @serializer.deserialize(@msg.data)
      end

      # @return [Integer]
      def stream_sequence
        metadata.sequence.stream
      end

      # @return [Integer]
      def consumer_sequence
        metadata.sequence.consumer
      end
    end
  end
end
