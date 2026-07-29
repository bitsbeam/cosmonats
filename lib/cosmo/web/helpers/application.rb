# frozen_string_literal: true

require "cosmo/web/renderer"

module Cosmo
  class Web
    module Helpers
      module Application
        include Renderer

        def render(template, locals = nil)
          defaults = { request: @request }
          locals = Hash(locals).merge(defaults)
          erb(template, locals)
        end

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

        def elapsed(value)
          elapsed = Time.now.to_i - value.to_i

          if elapsed < 60
            "#{elapsed}s"
          elsif elapsed < 3600
            "#{elapsed / 60}m #{elapsed % 60}s"
          else
            "#{elapsed / 3600}h #{(elapsed % 3600) / 60}m"
          end
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

        # Build the list of page numbers to render around the current page, with
        # `:gap` markers where numbers are skipped.
        #   pages(5, 20) # => [1, :gap, 3, 4, 5, 6, 7, :gap, 20]
        def pages(page, total_pages, window: 2)
          return [] if total_pages <= 1

          previous = nil
          candidates = ([1, total_pages] + ((page - window)..(page + window)).to_a).grep(1..total_pages).uniq.sort
          candidates.each_with_object([]) do |p, result|
            pagination_fill_gap(result, previous, p)
            result << p
            previous = p
          end
        end

        def current_page?(path)
          request_path = @request.path_info
          request_path = "/" if request_path.empty?
          request_path == path
        end

        def path_prefix?(*values)
          values.any? { |v| @request.path_info.start_with?(v) }
        end

        def referrer?(path)
          referrer_uri  = URI(@request.referrer)
          referrer_path = referrer_uri.path
          script_name   = @request.script_name
          referrer_path = referrer_path.delete_prefix(script_name) if script_name && !script_name.empty?
          referrer_path = "/" if referrer_path.empty?
          referrer_path == path
        end

        private

        def pagination_fill_gap(result, previous, page)
          return unless previous

          result << (previous + 1) if page - previous == 2
          result << :gap if page - previous > 2
        end
      end
    end
  end
end
