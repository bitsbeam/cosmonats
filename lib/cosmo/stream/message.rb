# frozen_string_literal: true

require "forwardable"

module Cosmo
  module Stream
    class Message
      extend Forwardable

      delegate %i[subject reply header metadata ack nack term in_progress] => :@msg
      delegate %i[timestamp num_delivered num_pending] => :metadata

      def initialize(msg, serializer: nil)
        @msg = msg
        @serializer = serializer || Serializer
      end

      def data
        @serializer.deserialize(@msg.data)
      end

      def stream_sequence
        metadata.sequence.stream
      end

      def consumer_sequence
        metadata.sequence.consumer
      end
    end
  end
end
