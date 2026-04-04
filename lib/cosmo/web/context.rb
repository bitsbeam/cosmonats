# frozen_string_literal: true

require "cosmo/web/helpers/application"

module Cosmo
  class Web
    class Context
      include Helpers::Application

      def initialize(locals, content_for = nil)
        @content_for = Hash(content_for)
        locals.each { |k, v| instance_variable_set("@#{k}", v) }
      end

      def binding # rubocop:disable Lint/UselessMethodDefinition
        super
      end

      def content_for(name)
        @content_for[name]
      end

      def content_for?(name)
        @content_for.key?(name)
      end
    end
  end
end
