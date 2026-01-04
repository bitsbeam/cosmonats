# frozen_string_literal: true

require "json"

module Cosmo
  module Utils
    module Json
      module_function

      def parse(value, default: nil, symbolize_names: true, **options)
        JSON.parse(value, options.merge(symbolize_names:))
      rescue TypeError, JSON::ParserError
        default
      end

      def dump(value, default: nil)
        ::JSON.generate(value)
      rescue TypeError, JSON::NestingError
        default
      end
    end
  end
end
