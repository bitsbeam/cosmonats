# frozen_string_literal: true

module Cosmo
  class Web
    # Geometry for the Overview's throughput chart: an area line of the successful runs per day and a bar per day for
    # the failed ones, drawn into a viewBox the page stretches to its width, axes and hover targets laid out in percent.
    class Throughput
      WIDTH = 1000
      HEIGHT = 220
      PLOT = 214
      FAILED = 54
      BAR = 22
      TICKS = 3
      LABELS = 5

      # @param series [Array<Hash>] +{ date:, count:, failed:, exec_ms: }+ per day, oldest first
      def initialize(series)
        @series = series
        @top = top(series.map { _1[:count] }.max.to_i)
        @failed_top = [series.map { _1[:failed] }.max.to_i, 1].max
      end

      # @return [Boolean]
      def empty?
        @series.all? { _1[:count].zero? && _1[:failed].zero? }
      end

      # @return [String] the path of the runs line
      def line
        @series.each_with_index.map { |day, index| "#{index.zero? ? "M" : "L"}#{x(index)} #{y(day[:count])}" }.join(" ")
      end

      # @return [String] the path of the area under the runs line
      def area
        "#{line} L#{x(@series.size - 1)} #{HEIGHT} L#{x(0)} #{HEIGHT} Z"
      end

      # @return [String] the path of the failure bars, one per day with failures
      def failures # rubocop:disable Metrics/AbcSize
        width = ((WIDTH / [@series.size, 1].max.to_f) * 0.42).clamp(2, BAR).round(1)
        @series.each_with_index.filter_map do |day, index|
          next if day[:failed].zero?

          height = [(day[:failed] / @failed_top.to_f) * FAILED, 1].max.round(1)
          "M#{(x(index) - (width / 2)).round(1)} #{HEIGHT} v#{-height} h#{width} v#{height} Z"
        end.join(" ")
      end

      # @return [String] the path of the horizontal grid lines
      def grid
        (0..TICKS).map { "M0 #{(HEIGHT - (PLOT * _1 / TICKS.to_f)).round(1)} H#{WIDTH}" }.join(" ")
      end

      # @return [Array<Integer>] the y axis values, top down
      def ticks
        TICKS.downto(0).map { (@top * _1 / TICKS.to_f).round }
      end

      # @return [Array<String>] the x axis labels, evenly spread
      def labels
        count = [LABELS, @series.size].min
        return [] if count.zero?

        (0...count).map { label(@series[count == 1 ? 0 : ((@series.size - 1) * _1 / (count - 1).to_f).round][:date]) }
      end

      # @return [Array<Hash>] per day the hover column +left+/+width+ and the dot +top+, in percent, with the numbers
      def points # rubocop:disable Metrics/AbcSize
        slot = 100.0 / [@series.size, 1].max
        @series.each_with_index.map do |day, index|
          center = @series.size == 1 ? 50.0 : x(index) / WIDTH * 100
          day.merge(left: (center - (slot / 2)).round(2), width: slot.round(2), center: center,
                    top: (y(day[:count]) / HEIGHT * 100).round(2), label: label(day[:date]))
        end
      end

      private

      def x(index)
        return WIDTH / 2.0 if @series.size == 1

        (index * WIDTH / (@series.size - 1).to_f).round(1)
      end

      def y(value)
        (HEIGHT - (value / @top.to_f * PLOT)).round(1)
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
