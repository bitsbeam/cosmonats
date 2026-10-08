# frozen_string_literal: true

module Cosmo
  class Web
    # Geometry for the Metrics tab's SVG chart: a bar per day for the number of runs on the left axis, and a line for
    # the average execution time on the right one.
    class Chart
      WIDTH = 760
      HEIGHT = 240
      TOP = 16
      BOTTOM = 212
      LEFT = 52
      RIGHT = 700
      TICKS = 4
      LABELS = 10

      # @param series [Array<Hash>] +{ date:, count:, exec_ms: }+ per day, oldest first
      def initialize(series)
        @series = series
        @count_top = top(series.map { _1[:count] }.max.to_i)
        @exec_top = top(series.filter_map { _1[:exec_ms] }.max.to_f)
      end

      # @return [Boolean]
      def empty?
        @series.all? { _1[:count].zero? }
      end

      # @return [Array<Hash>] +{ x:, y:, width:, height:, title: }+
      def bars # rubocop:disable Metrics/AbcSize
        @series.each_with_index.map do |day, index|
          height = scale(day[:count], @count_top)
          { x: (slot_x(index) + (slot * 0.15)).round(1), y: (BOTTOM - height).round(1), width: (slot * 0.7).round(1),
            height: height.round(1), title: "#{label(day[:date])}: #{day[:count]} run(s)" }
        end
      end

      # @return [Array<Hash>] +{ x:, y:, title: }+ for the days with an average
      def points
        @series.each_with_index.filter_map do |day, index|
          next unless day[:exec_ms]

          { x: (slot_x(index) + (slot / 2)).round(1), y: (BOTTOM - scale(day[:exec_ms], @exec_top)).round(1),
            title: "#{label(day[:date])}: #{day[:exec_ms]} ms on average" }
        end
      end

      # @return [String] the +points+ attribute of the execution time polyline
      def line
        points.map { "#{_1[:x]},#{_1[:y]}" }.join(" ")
      end

      # @return [Array<Hash>] +{ y:, count:, exec_ms: }+ per horizontal grid line, bottom up
      def ticks
        (0..TICKS).map do |step|
          { y: (BOTTOM - ((BOTTOM - TOP) * step / TICKS.to_f)).round(1),
            count: (@count_top * step / TICKS.to_f).round, exec_ms: (@exec_top * step / TICKS.to_f).round }
        end
      end

      # @return [Array<Hash>] +{ x:, text: }+, thinned out to at most LABELS
      def labels
        every = (@series.size / LABELS.to_f).ceil.clamp(1, nil)
        @series.each_with_index.filter_map do |day, index|
          { x: (slot_x(index) + (slot / 2)).round(1), text: label(day[:date]) } if (index % every).zero?
        end
      end

      private

      def slot
        (RIGHT - LEFT) / [@series.size, 1].max.to_f
      end

      def slot_x(index)
        LEFT + (slot * index)
      end

      def scale(value, top)
        top.zero? ? 0 : (BOTTOM - TOP) * value / top.to_f
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
