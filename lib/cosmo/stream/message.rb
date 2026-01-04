# frozen_string_literal: true

require "forwardable"

module Cosmo
  module Stream
    class Message
      extend Forwardable

      delegate %i[subject reply header ack nack term] => :@msg

      def initialize(msg, serializer: nil)
        @msg = msg
        @serializer = serializer || Serializer
      end

      def data
        @serializer.deserialize(@msg.data)
      end
    end
  end
end
