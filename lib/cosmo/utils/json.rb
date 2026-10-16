# frozen_string_literal: true

require "json"

module Cosmo
  module Utils
    module Json
      module_function

      # @param value [String]
      # @param default [Object] returned when +value+ is not valid JSON
      # @param symbolize_names [Boolean]
      # @param options [Hash] passed on to +JSON.parse+
      # @return [Object]
      def parse(value, default: nil, symbolize_names: true, **options)
        JSON.parse(value, **options, symbolize_names:)
      rescue TypeError, JSON::ParserError
        default
      end

      # @param value [Object]
      # @param default [Object] returned when +value+ cannot be generated
      # @return [String, Object]
      def dump(value, default: nil)
        ::JSON.generate(value)
      rescue TypeError, JSON::NestingError
        default
      end
    end
  end
end
