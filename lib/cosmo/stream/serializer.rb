# frozen_string_literal: true

require "json"

module Cosmo
  module Stream
    module Serializer
      module_function

      # @param data [Object]
      # @return [String, nil] JSON, or nil when +data+ cannot be dumped
      def serialize(data)
        Utils::Json.dump(data)
      end

      # @param payload [String]
      # @return [Object, nil] the parsed JSON with string keys, or nil when it is malformed
      def deserialize(payload)
        Utils::Json.parse(payload, symbolize_names: false)
      end
    end
  end
end
