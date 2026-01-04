# frozen_string_literal: true

require "cosmo/job/data"
require "cosmo/job/processor"

module Cosmo
  module Job
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def options(stream: nil, retry: nil, dead: nil)
        default_options.merge!({ stream:, retry:, dead: }.compact)
      end

      def perform(*args, async: true, **options)
        data = Data.new(name, args, default_options.merge(options))
        unless async
          payload = Utils::Json.parse(data.to_args[1])
          raise ArgumentError, "Cannot parse payload" unless payload

          new.perform(*payload[:args])
          return
        end

        Publisher.publish_job(data)
      end

      def perform_async(*args)
        perform(*args)
      end

      def perform_at(timestamp, *args)
        perform(*args, at: timestamp)
      end

      def perform_in(interval, *args)
        perform(*args, in: interval)
      end

      def perform_sync(*args)
        perform(*args, async: false)
      end

      def default_options
        @default_options ||= (superclass.respond_to?(:default_options) ? superclass.default_options : Data::DEFAULTS).dup
      end

      private

      def client
        @client ||= Client.instance
      end
    end

    def perform(...)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end

    def jid
      Thread.current[:cosmo_jid]
    end
  end
end
