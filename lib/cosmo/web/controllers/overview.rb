# frozen_string_literal: true

require "cosmo/web/controllers/application"
require "cosmo/web/throughput"

module Cosmo
  class Web
    module Controllers
      class Overview < Application
        RANGES = [7, 30].freeze
        CELLS = 64
        RUNNING = 9
        PROCESSES = 3
        BATCHES = 100

        # Renders the overview page.
        #
        # @return [Array] the Rack response
        def index
          content_for :title, "Overview"
          content_for :subtitle, "Everything beamed through NATS, live."
          ok render("overview/index", { metrics: Config.metrics.enabled }, layout: true)
        end

        # Renders the overview's KPI cards.
        #
        # @return [Array] the Rack response
        def _kpis
          ok render("overview/_kpis", API::Stats.summary)
        end

        # Renders the throughput chart for the requested range, or 404 while metrics are disabled.
        #
        # @return [Array] the Rack response
        def _throughput
          return not_found unless Config.metrics.enabled

          days = RANGES.include?(params["days"].to_i) ? params["days"].to_i : RANGES.first
          chart = Throughput.new(API::Stats::Metrics.instance.daily(days:))
          ok render("overview/_throughput", { chart:, days:, ranges: RANGES })
        end

        # Renders the worker processes and a cell per thread, busy or idle.
        #
        # @return [Array] the Rack response
        def _workers
          registry = API::Stats::Processes.instance
          threads = registry.threads
          cells, busy = worker_cells(threads)
          ok render("overview/_workers", { processes: registry.list(limit: PROCESSES), total: registry.size,
                                           cells:, hidden: [threads - CELLS, 0].max, busy:, threads: })
        end

        # Renders a sample of the running jobs.
        #
        # @return [Array] the Rack response
        def _running
          ok render("overview/_running", { jobs: API::Stats.running(RUNNING), total: API::Stats.busy })
        end

        # Renders the sidebar's count badges. Batches are only counted up to BATCHES; past that the badge
        # reads "100+".
        #
        # @return [Array] the Rack response
        def _badges
          badges = { jobs: API::Stats.enqueued, streams: visible_streams.size }
          badges[:crons] = API::Cron.instance.all.size if Config.scheduled.enabled
          batches = API::Batch.count(limit: BATCHES + 1)
          badges[:batches] = batches > BATCHES ? "#{BATCHES}+" : batches
          ok render("overview/_badges", { badges: })
        end

        private

        def worker_cells(threads)
          busy = API::Stats.busy_streams.select { _2.positive? }
          cells = busy.flat_map { |stream, count| Array.new([count, CELLS].min, stream) }.first(CELLS)
          cells += Array.new((threads - busy.values.sum).clamp(0, CELLS - cells.size))
          [cells, busy.values.sum]
        end

        def visible_streams
          API::Stream.all.reject { _1.name.start_with?("KV_", "_cosmo") }
        end
      end
    end
  end
end
