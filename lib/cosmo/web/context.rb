# frozen_string_literal: true

require "cosmo/web/helpers/application"

module Cosmo
  class Web
    class Context
      include Helpers::Application

      # @param locals [Hash{Symbol => Object}] set as instance variables the view reads
      # @param content_for [Hash{Symbol => String}, nil] the blocks the layout yields
      def initialize(locals, content_for = nil)
        @content_for = Hash(content_for)
        locals.each { |k, v| instance_variable_set("@#{k}", v) }
      end

      # @param name [Symbol]
      # @return [String, nil] the content captured under +name+
      def content_for(name)
        @content_for[name]
      end

      # @param name [Symbol]
      # @return [Boolean] whether content was captured under +name+
      def content_for?(name)
        @content_for.key?(name)
      end
    end
  end
end
