# frozen_string_literal: true

require "json"

module Cosmo
  module Stream
    module Serializer
      module_function

      def serialize(data)
        Utils::Json.dump(data)
      end

      def deserialize(payload)
        Utils::Json.parse(payload, symbolize_names: false)
      end
    end
  end
end
