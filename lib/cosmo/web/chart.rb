# frozen_string_literal: true

module Cosmo
  class Web
    # Geometry for the Metrics tab's chart: a bar per day for the number of runs on the left axis and a line for the
    # average execution time on the right one, drawn into a viewBox the page stretches to its width, axes and hover
    # targets laid out in percent.
    class Chart
      WIDTH = 1000
      HEIGHT = 220
      PLOT = 214
      TICKS = 3
      LABELS = 6
      BAR = 28

      # @param series [Array<Hash>] +{ date:, count:, failed:, exec_ms:, wait_ms: }+ per day, oldest first
      def initialize(series)
        @series = series
        @count_top = top(series.map { _1[:count] }.max.to_i)
        @exec_top = top(series.filter_map { _1[:exec_ms] }.max.to_f)
      end

      # @return [Boolean]
      def empty?
        @series.all? { _1[:count].zero? }
      end

      # @return [String] the path of the run bars, one per day with runs
      def bars
        width = (slot * 0.6).clamp(2, BAR).round(1)
        @series.each_with_index.filter_map do |day, index|
          next if day[:count].zero?

          height = scale(day[:count], @count_top).round(1)
          "M#{(center(index) - (width / 2)).round(1)} #{HEIGHT} v#{-height} h#{width} v#{height} Z"
        end.join(" ")
      end

      # @return [String] the path of the execution time line, broken over days without a successful run
      def line
        drawing = false
        @series.each_with_index.filter_map do |day, index|
          unless day[:exec_ms]
            drawing = false
            next
          end

          command = drawing ? "L" : "M"
          drawing = true
          "#{command}#{center(index).round(1)} #{exec_y(day[:exec_ms])}"
        end.join(" ")
      end

      # @return [String] the path of the horizontal grid lines
      def grid
        (0..TICKS).map { "M0 #{(HEIGHT - (PLOT * _1 / TICKS.to_f)).round(1)} H#{WIDTH}" }.join(" ")
      end

      # @return [Array<Hash>] +{ count:, exec_ms: }+ per grid line, top down
      def ticks
        TICKS.downto(0).map do |step|
          { count: (@count_top * step / TICKS.to_f).round, exec_ms: (@exec_top * step / TICKS.to_f).round }
        end
      end

      # @return [Array<Hash>] +{ left:, text: }+ x axis labels in percent, thinned out to at most LABELS
      def labels
        every = (@series.size / LABELS.to_f).ceil.clamp(1, nil)
        @series.each_with_index.filter_map do |day, index|
          { left: percent(center(index)), text: label(day[:date]) } if (index % every).zero?
        end
      end

      # @return [Array<Hash>] per day the hover column +left+/+width+, its +center+, the execution time dot +dot+
      #   (nil without one) and the bar top +top+, in percent, with the day's numbers
      def points # rubocop:disable Metrics/AbcSize
        @series.each_with_index.map do |day, index|
          bar_top = HEIGHT - scale(day[:count], @count_top)
          day.merge(left: percent(slot * index), width: percent(slot), center: percent(center(index)),
                    dot: day[:exec_ms] && percent(exec_y(day[:exec_ms]), HEIGHT), top: percent(bar_top, HEIGHT),
                    label: label(day[:date]))
        end
      end

      private

      def slot
        WIDTH / [@series.size, 1].max.to_f
      end

      def center(index)
        slot * (index + 0.5)
      end

      def exec_y(value)
        (HEIGHT - scale(value, @exec_top)).round(1)
      end

      def scale(value, top)
        top.zero? ? 0 : PLOT * value / top.to_f
      end

      def percent(value, total = WIDTH)
        (value / total.to_f * 100).round(2)
      end

      # The smallest "nice" axis maximum (1, 2 or 5 times a power of ten per tick) at or above +max+.
      def top(max)
        return TICKS if max.zero?

        raw = max / TICKS.to_f
        magnitude = 10**Math.log10(raw).floor
        step = [1, 2, 5, 10].map { _1 * magnitude }.find { _1 >= raw }
        step * TICKS
      end

      def label(date)
        "#{date[4, 2]}/#{date[6, 2]}"
      end
    end
  end
end
