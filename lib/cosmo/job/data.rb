# frozen_string_literal: true

require "json"

module Cosmo
  module Job
    class Data
      DEFAULTS = { stream: :default, retry: 3, dead: true, limit: nil }.freeze

      # @return [Integer] +max_retries+ from the config, or the built-in default
      def self.default_retry
        Config[:max_retries] || DEFAULTS[:retry]
      end

      attr_reader :jid

      # @param class_name [String]
      # @param args [Array]
      # @param options [Hash, nil] job options, +stream:+ is required
      # @raise [ArgumentError] when no stream is given
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

      # @return [String, nil] the id of the batch the job belongs to
      def batch_id
        @options[:batch_id]
      end

      # @param target [Boolean] true returns the job's own stream even when it is delayed
      # @return [Symbol] the stream the job is published to: +scheduled+ for a delayed job unless +target+
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
        headers = { NATS::JetStream::Header::MSG_ID => jid }
        return headers unless @at

        target = stream(target: true)
        headers.merge("X-Execute-At" => @at.to_i, "X-Stream" => target, "X-Subject" => subject_for(target))
      end

      # @return [Hash{Symbol => Object}] the published payload
      def as_json
        json = { jid: jid, class: @class_name, args: @args, retry: retries, dead: dead }
        batch_id ? json.merge(batch_id: batch_id) : json
      end

      # @param _args [Array] ignored, accepted for +JSON.generate+ compatibility
      # @return [String, nil]
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
