# frozen_string_literal: true

require "json"

module Cosmo
  module Job
    class Data
      DEFAULTS = { stream: :default, retry: 3, dead: true }.freeze

      attr_reader :jid

      def initialize(class_name, args, options = nil)
        @class_name = class_name
        @args = args
        @options = Hash(options)
        validate!

        @at = @options[:at].to_i if @options[:at]
        @at ||= Time.now.to_i + @options[:in].to_i if @options[:in]
        @subject = @options[:subject] if @options[:subject]

        @jid = SecureRandom.hex(12)
      end

      def stream(target: false)
        return @options[:stream] if target

        @at ? :scheduled : @options[:stream]
      end

      def subject(target: false)
        ["jobs", stream(target:), Utils::String.underscore(@class_name)]
      end

      def as_json
        {
          jid: jid,
          class: @class_name,
          args: @args,
          retry: retries,
          dead: dead
        }
      end

      def to_json(*_args)
        Utils::Json.dump(as_json)
      end

      def to_args
        headers = { "Nats-Msg-Id" => jid }
        if @at
          headers.merge!("X-Execute-At" => @at.to_i,
                         "X-Stream" => stream(target: true),
                         "X-Subject" => subject(target: true).join("."))
        end
        [@subject || subject.join("."), to_json, { stream: stream, header: headers }]
      end

      private

      def validate!
        raise ArgumentError, "stream is not provided" unless @options[:stream]
      end

      def retries
        @options[:retry].nil? ? DEFAULTS[:retry] : @options[:retry]
      end

      def dead
        @options[:dead].nil? ? DEFAULTS[:dead] : @options[:dead]
      end
    end
  end
end
