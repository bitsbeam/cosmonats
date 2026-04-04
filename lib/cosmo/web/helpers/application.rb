# frozen_string_literal: true

require "cosmo/web/renderer"

module Cosmo
  class Web
    module Helpers
      module Application
        include Renderer

        def format_bytes(bytes)
          b = bytes.to_i
          return "0 B" if b.zero?

          sizes = %w[B KB MB GB TB]
          i = [(Math.log(b) / Math.log(1024)).floor, sizes.size - 1].min
          "#{(b / (1024.0**i)).round(2)} #{sizes[i]}"
        end

        def format_numbers(num)
          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
        end

        def format_timestamp(value)
          return "N/A" unless value

          Time.at(value.to_f).strftime("%Y-%m-%d %H:%M:%S")
        rescue StandardError
          value.to_s
        end

        def time_until(value)
          return "N/A" unless value

          diff = value.to_f - Time.now.to_f
          return "Ready" if diff <= 0
          return "#{diff.to_i}s" if diff < 60
          return "#{(diff / 60).to_i}m" if diff < 3_600
          return "#{(diff / 3_600).to_i}h" if diff < 86_400

          "#{(diff / 86_400).to_i}d"
        end

        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def u(value)
          Rack::Utils.escape(value.to_s)
        end

        def current_page?(path)
          request_path = @request.path_info
          request_path = "/" if request_path.empty?
          request_path == url_for(path)
        end
      end
    end
  end
end
