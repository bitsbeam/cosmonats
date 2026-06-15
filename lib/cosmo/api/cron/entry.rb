# frozen_string_literal: true

require "securerandom"
require "json"

module Cosmo
  module API
    class Cron
      # Value object representing a single cron schedule entry.
      # Each schedule maps one job class (and optional args) to a NATS 2.14 message schedule.
      #
      # NATS 2.14 message scheduling uses a 6-field cron format:
      #   second minute hour day-of-month month day-of-week
      #
      # @-shortcuts (@daily, @every 5m, @at ...) are passed through unchanged —
      # the server understands them natively. Plain 5-field UNIX cron expressions
      # need a seconds field prepended to become valid 6-field expressions.
      #
      #   "0 9 * * 1-5"  →  "0 0 9 * * 1-5"   (at 09:00 on weekdays)
      #   "@daily"        →  "@daily"            (unchanged)
      class Entry
        SUBJECT_PREFIX = "cosmo.cron"

        def self.normalize_expression(expr)
          str = expr.to_s.strip
          return str if str.start_with?("@")

          fields = str.split
          fields.size == 5 ? "0 #{str}" : str
        end

        attr_reader :class_name, :stream, :expression, :args, :timezone, :name

        # @param class_name [String] Fully-qualified Ruby class name (e.g. "ReportJob")
        # @param stream     [String] Target job stream name (e.g. "default")
        # @param expression [String] NATS schedule expression (@daily, @every 5m, "0 0 9 * * 1-5", etc.)
        # @param args       [Array]  Arguments passed to the job's +perform+ method
        # @param timezone   [String, nil] IANA timezone name (e.g. "America/New_York"). Cron expressions only.
        # @param name       [String, Symbol, nil] Disambiguates multiple schedules on the same class.
        def initialize(class_name:, stream:, expression:, args: [], timezone: nil, name: nil)
          @class_name = class_name.to_s
          @stream     = stream.to_s
          @expression = self.class.normalize_expression(expression)
          @args       = Array(args)
          @timezone   = timezone
          @name       = name&.to_s
        end

        # Subject where the schedule message lives in NATS (one per unique schedule).
        # e.g. "cosmo.cron.default.report_job" or "cosmo.cron.default.report_job.monthly"
        def schedule_subject
          parts = [SUBJECT_PREFIX, @stream, job_name]
          parts << @name if @name
          parts.join(".")
        end

        # Subject where NATS fires the generated job message.
        # Must be a subject covered by the same stream.
        def target_subject
          "jobs.#{@stream}.#{job_name}"
        end

        def job_name
          @job_name ||= Utils::String.underscore(@class_name)
        end

        def as_json
          {
            class: @class_name,
            stream: @stream,
            schedule: @expression,
            timezone: @timezone,
            args: @args,
            name: @name,
            schedule_subject: schedule_subject,
            target_subject: target_subject
          }.compact
        end

        # JSON payload sent as the body of the schedule message.
        # Mirrors the format produced by Job::Data so the job processor can handle it.
        def job_payload
          Utils::Json.dump({
                             jid: SecureRandom.hex(12),
                             class: @class_name,
                             args: @args,
                             retry: ::Cosmo::Job::Data::DEFAULTS[:retry],
                             dead: ::Cosmo::Job::Data::DEFAULTS[:dead]
                           })
        end

        def to_s
          "#<Cosmo::API::Cron::Entry class=#{@class_name} expression=#{@expression} stream=#{@stream}>"
        end
        alias inspect to_s
      end
    end
  end
end
