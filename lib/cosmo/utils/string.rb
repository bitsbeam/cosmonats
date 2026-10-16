# frozen_string_literal: true

module Cosmo
  module Utils
    module String
      module_function

      # @param value [String, Symbol, Class] e.g. "Cosmo::SendEmailJob"
      # @return [String] e.g. "cosmo-send_email_job"
      def underscore(value)
        value
          .to_s
          .gsub("::", "-")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      # @param value [String] a constant name
      # @return [Object, nil] the constant, or nil when it is not defined
      def safe_constantize(value)
        Object.const_get(value)
      rescue NameError
        # nop
      end
    end
  end
end
