# frozen_string_literal: true

module Cosmo
  module Utils
    module String
      module_function

      def underscore(value)
        value
          .to_s
          .gsub("::", "-")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      def safe_constantize(value)
        Object.const_get(value)
      rescue NameError
        # nop
      end
    end
  end
end
