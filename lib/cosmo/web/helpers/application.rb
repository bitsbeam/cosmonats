# frozen_string_literal: true

require "cosmo/web/renderer"

module Cosmo
  class Web
    module Helpers
      module Application
        include Renderer

        # Seconds between htmx auto-refreshes. Override with COSMO_WEB_POLL_INTERVAL.
        POLL_INTERVAL = 5

        def poll_interval
          @poll_interval ||= ENV.fetch("COSMO_WEB_POLL_INTERVAL", POLL_INTERVAL).to_i
        end

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

        # @param millis [Numeric, nil]
        # @return [String] e.g. "340 ms", "1.25 s", "2m 3s", or "—" without a value
        def duration(millis)
          return "—" unless millis
          return "#{millis.round} ms" if millis < 1_000
          return "#{(millis / 1_000.0).round(2)} s" if millis < 60_000

          "#{(millis / 60_000).floor}m #{((millis % 60_000) / 1_000).round}s"
        end

        def elapsed(value)
          elapsed = Time.now.to_i - value.to_i

          if elapsed < 60
            "#{elapsed}s"
          elsif elapsed < 3600
            "#{elapsed / 60}m #{elapsed % 60}s"
          elsif elapsed < 86_400
            "#{elapsed / 3600}h #{(elapsed % 3600) / 60}m"
          else
            "#{elapsed / 86_400}d #{(elapsed % 86_400) / 3600}h"
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

        # @return [String] e.g. "940", "18.9k", "1.28M"
        def compact_number(num)
          n = num.to_i
          return format("%.2fM", n / 1e6).sub(/\.?0+M\z/, "M") if n >= 1_000_000
          return format("%.1fk", n / 1e3).sub(/\.0k\z/, "k") if n >= 10_000

          format_numbers(n)
        end

        # @param seconds [Numeric, nil]
        # @return [String] e.g. "45s", "30m", "7d", or "—" without a value
        def format_span(seconds)
          s = seconds.to_i
          return "—" unless s.positive?

          { 86_400 => "d", 3_600 => "h", 60 => "m" }.each { |size, unit| return "#{(s / size.to_f).round(1).to_s.delete_suffix(".0")}#{unit}" if s >= size }
          "#{s}s"
        end

        # A stable chart color per name, one of the palette's five hues: job streams take them in name order, so the
        # first five never share one, anything else by a hash of its name.
        def hue(name)
          @hues ||= API::Stream.jobs.map(&:name).sort.each_with_index.to_h
          index = @hues.fetch(name.to_s) { Zlib.crc32(name.to_s) }
          "var(--c#{(index % 5) + 1})"
        end

        # @return [Array<Hash>] the sidebar entries, +:key+, +:label+ and +:path+, for the enabled pages
        def nav_items
          items = [%w[overview Overview /], %w[jobs Jobs /jobs], %w[streams Streams /streams]]
          items << %w[crons Crons /crons] if Config.scheduled.enabled
          items << %w[batches Batches /batches]
          items << %w[metrics Metrics /metrics] if Config.metrics.enabled
          items.map { |key, label, path| { key:, label:, path: } }
        end

        # @return [String] the nav key of the page being rendered
        def current_section
          path = @request.path_info
          return "overview" if path.empty? || path == "/" || path.start_with?("/processes")

          path.split("/")[1].to_s
        end

        # @return [Hash] the connected NATS server's +:url+, +:name+ and +:version+, empty while unknown
        def nats_server
          connection = Client.instance.nc
          info = connection.server_info || {}
          uri = connection.connected_server
          name = info[:server_name] unless info[:server_name] == info[:server_id]
          { url: uri && "#{uri.host}:#{uri.port}", name:, version: info[:version] }.compact
        rescue StandardError
          {}
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
