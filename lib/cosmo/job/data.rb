# frozen_string_literal: true

require "json"

module Cosmo
  module Job
    class Data
      DEFAULTS = { stream: :default, retry: 3, dead: true, limit: nil }.freeze

      def self.default_retry
        Config[:max_retries] || DEFAULTS[:retry]
      end

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

      def batch_id
        @options[:batch_id]
      end

      def stream(target: false)
        return @options[:stream] if target

        @at ? :scheduled : @options[:stream]
      end

      # @return [String] the subject the job is published to: the custom +subject:+ option, or the one derived
      #   from its stream and class
      def subject
        @subject || subject_for(stream)
      end

      # @return [Hash{String => String, Integer}] dedup id, plus where to dispatch a delayed job once it is due
      def headers
        headers = { "Nats-Msg-Id" => jid }
        return headers unless @at

        target = stream(target: true)
        headers.merge("X-Execute-At" => @at.to_i, "X-Stream" => target, "X-Subject" => subject_for(target))
      end

      def as_json
        json = { jid: jid, class: @class_name, args: @args, retry: retries, dead: dead }
        batch_id ? json.merge(batch_id: batch_id) : json
      end

      def to_json(*_args)
        Utils::Json.dump(as_json)
      end

      private

      def subject_for(stream)
        "jobs.#{stream}.#{Utils::String.underscore(@class_name)}"
      end

      def validate!
        raise ArgumentError, "stream is not provided" unless @options[:stream]
      end

      def retries
        return self.class.default_retry if @options[:retry].nil?
        return 0 if @options[:retry] == false

        @options[:retry]
      end

      def dead
        @options[:dead].nil? ? DEFAULTS[:dead] : @options[:dead]
      end
    end
  end
end
