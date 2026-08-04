# frozen_string_literal: true

module Cosmo
  module Utils
    # Parses human-friendly duration strings ("20s", "1h", "7d") into seconds, so
    # config values don't have to be spelled out as bare, uncommented integers.
    # Numbers pass through unchanged, since existing config already uses plain seconds.
    module Duration
      UNITS = {
        "s" => 1,
        "m" => 60,
        "h" => 3600,
        "d" => 86_400,
        "w" => 604_800,
        "mo" => 2_592_000, # 30 days
        "y" => 31_536_000
      }.freeze

      module_function

      def parse(value)
        return value if value.is_a?(Numeric)

        str = value.to_s
        match = str.match(/\A(\d+)(mo|[smhdwy])\z/)
        return match[1].to_i * UNITS[match[2]] if match
        return str.to_f if str.match?(/\A\d+(\.\d+)?\z/)

        raise ArgumentError, "invalid duration: #{value}"
      end
    end
  end
end
