# frozen_string_literal: true

require "time"

module Cosmo
  module API
    class Cron
      # Describes a cron schedule in plain English, in the manner of crontab.guru.
      #
      # Understands what the server accepts: 5-field and 6-field (leading seconds) cron expressions with lists,
      # ranges, steps and month/weekday names, the calendar shortcuts (+@daily+...), +@every <duration>+ and
      # +@at <RFC 3339 time>+. Anything it can't make sense of is described as an empty string, never an error.
      #
      #   Describer.call("0 9 * * 1-5")  # => "At 09:00 on every day-of-week from Monday through Friday"
      #   Describer.call("*/5 * * * *")  # => "At every 5th minute"
      #   Describer.call("@every 90s")   # => "Every 90 seconds"
      class Describer
        MONTHS = %w[January February March April May June July August September October November December].freeze
        WEEKDAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
        MACROS = {
          "@yearly" => "0 0 0 1 1 *",
          "@annually" => "0 0 0 1 1 *",
          "@monthly" => "0 0 0 1 * *",
          "@weekly" => "0 0 0 * * 0",
          "@daily" => "0 0 0 * * *",
          "@midnight" => "0 0 0 * * *",
          "@hourly" => "0 0 * * * *"
        }.freeze
        DURATION_UNITS = { "h" => "hour", "m" => "minute", "s" => "second", "ms" => "millisecond" }.freeze
        DURATION = /\A(?:\d+(?:ms|h|m|s))+\z/
        TERM = %r{\A(?<from>\*|\?|\w+)(?:-(?<to>\w+))?(?:/(?<step>\d+))?\z}
        ORDINAL_SUFFIXES = { 1 => "st", 2 => "nd", 3 => "rd" }.freeze

        Term = Data.define(:from, :to, :step, :wild)
        Spec = Data.define(:unit, :range, :labels, :names)

        SPECS = [
          Spec.new("second", 0..59, nil, {}),
          Spec.new("minute", 0..59, nil, {}),
          Spec.new("hour", 0..23, nil, {}),
          Spec.new("day-of-month", 1..31, nil, {}),
          Spec.new("month", 1..12, MONTHS, MONTHS.each_with_index.to_h { |name, i| [name[0, 3].upcase, i + 1] }),
          Spec.new("day-of-week", 0..7, WEEKDAYS, WEEKDAYS.each_with_index.to_h { |name, i| [name[0, 3].upcase, i] })
        ].freeze

        # @param expression [String, nil] a cron expression or @-shortcut
        # @return [String] the description, or an empty string when the expression can't be parsed
        def self.call(expression)
          new(expression).call
        end

        # @param expression [String, nil]
        def initialize(expression)
          @expression = expression.to_s.strip
        end

        # @return [String]
        def call
          text = MACROS.fetch(@expression.downcase, @expression)
          case text
          when /\A@every\s+(\S+)\z/i then interval(Regexp.last_match(1).downcase)
          when /\A@at\s+(\S+)\z/i then instant(Regexp.last_match(1))
          when /\A@/ then ""
          else cron(text)
          end
        end

        private

        def interval(text)
          return "" unless DURATION.match?(text)

          parts = text.scan(/(\d+)(ms|h|m|s)/).map { |amount, unit| [amount.to_i, DURATION_UNITS.fetch(unit)] }
          parts.reject! { |amount, _| amount.zero? }
          return "" if parts.empty?
          return "Every #{parts.first.last}" if parts.one? && parts.first.first == 1

          "Every #{sentence(parts.map { |amount, unit| pluralize(amount, unit) })}"
        end

        def pluralize(amount, unit)
          "#{amount} #{unit}#{"s" unless amount == 1}"
        end

        def instant(text)
          Time.iso8601(text)
          "Once at #{text}"
        rescue ArgumentError
          ""
        end

        def cron(text)
          fields = text.split
          fields.unshift("0") if fields.size == 5
          return "" unless fields.size == SPECS.size

          terms = fields.zip(SPECS).map { |field, spec| parse(field, spec) }
          return "" unless terms.all?

          seconds, minutes, hours, days, months, weekdays = terms
          [time(seconds, minutes, hours), weekday_clause(days, weekdays), month_clause(months)].reject(&:empty?).join(" ")
        end

        def parse(field, spec)
          terms = field.split(",", -1).map { |part| term(part, spec) }
          terms if terms.all?
        end

        def term(part, spec)
          match = TERM.match(part)
          step = match && (match[:step]&.to_i || 1)
          return unless step&.positive?

          if %w[* ?].include?(match[:from])
            Term.new(spec.range.min, spec.range.max, step, true) unless match[:to]
          else
            bounded(match, step, spec)
          end
        end

        def bounded(match, step, spec)
          from = number(match[:from], spec)
          to = number(match[:to], spec) if match[:to]
          to ||= match[:step] ? spec.range.max : from
          Term.new(from, to, step, false) if from && to && from <= to
        end

        def number(token, spec)
          value = token.match?(/\A\d+\z/) ? token.to_i : spec.names[token.upcase]
          value if value && spec.range.cover?(value)
        end

        def time(seconds, minutes, hours)
          return clock(seconds, minutes, hours) if [seconds, minutes, hours].all? { |terms| single?(terms) }
          return "Every second" if [seconds, minutes, hours].all? { |terms| wild?(terms) }
          return "Every minute" if zero?(seconds) && wild?(minutes) && wild?(hours)

          parts = [phrase(minutes, SPECS[1])]
          parts.unshift(phrase(seconds, SPECS[0])) unless zero?(seconds)
          text = "At #{parts.join(", ")}"
          wild?(hours) ? text : "#{text} past #{phrase(hours, SPECS[2])}"
        end

        def clock(seconds, minutes, hours)
          time = format("%<hours>02d:%<minutes>02d", hours: hours.first.from, minutes: minutes.first.from)
          time += format(":%02d", seconds.first.from) unless zero?(seconds)
          "At #{time}"
        end

        def weekday_clause(days, weekdays)
          clauses = []
          clauses << "on #{phrase(days, SPECS[3])}" unless wild?(days)
          clauses << "on #{phrase(weekdays, SPECS[5])}" unless wild?(weekdays)
          clauses.join(" and ")
        end

        def month_clause(months)
          wild?(months) ? "" : "in #{phrase(months, SPECS[4])}"
        end

        def phrase(terms, spec)
          return every(terms.first, spec) if terms.one? && ranged?(terms.first)

          values = terms.map { |term| ranged?(term) ? every(term, spec) : label(term.from, spec) }
          spec.labels ? sentence(values) : "#{spec.unit} #{sentence(values)}"
        end

        def every(term, spec)
          step = term.step > 1 ? "#{ordinal(term.step)} " : ""
          text = "every #{step}#{spec.unit}"
          return text if term.wild

          "#{text} from #{label(term.from, spec)} through #{label(term.to, spec)}"
        end

        def label(value, spec)
          spec.labels ? spec.labels[(value - spec.range.min) % spec.labels.size] : value.to_s
        end

        def ranged?(term)
          term.from != term.to || term.step > 1
        end

        def single?(terms)
          terms.one? && !ranged?(terms.first)
        end

        def wild?(terms)
          terms.one? && terms.first.wild && terms.first.step == 1
        end

        def zero?(terms)
          single?(terms) && terms.first.from.zero?
        end

        def ordinal(number)
          suffix = (11..13).cover?(number % 100) ? "th" : ORDINAL_SUFFIXES.fetch(number % 10, "th")
          "#{number}#{suffix}"
        end

        def sentence(values)
          return values.first if values.one?

          "#{values[0...-1].join(", ")} and #{values.last}"
        end
      end
    end
  end
end
