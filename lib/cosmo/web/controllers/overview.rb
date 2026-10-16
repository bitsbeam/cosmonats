# frozen_string_literal: true

require "cosmo/web/controllers/application"
require "cosmo/web/throughput"

module Cosmo
  class Web
    module Controllers
      class Overview < Application
        RANGES = [7, 30].freeze
        CELLS = 256
        RUNNING = 9
        PROCESSES = 5

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
        def _workers # rubocop:disable Metrics/AbcSize
          processes = API::Stats::Processes.instance.list(limit: API::Stats::Processes.instance.size.clamp(1, nil))
          busy = API::Stats::Busy.instance.all.group_by { _1[:worker] }
          cells = processes.flat_map { worker_cells(_1, busy) }
          ok render("overview/_workers", { processes: processes.first(PROCESSES), total: processes.size,
                                           cells: cells.first(CELLS), hidden: [cells.size - CELLS, 0].max,
                                           busy: cells.count(&:itself), threads: cells.size })
        end

        # Renders the longest running jobs.
        #
        # @return [Array] the Rack response
        def _running
          jobs = API::Stats::Busy.instance.all.sort_by { _1[:started_at].to_i }.first(RUNNING)
          jobs = jobs.map { _1.merge(data: Utils::Json.parse(_1[:data]) || {}) }
          ok render("overview/_running", { jobs:, total: API::Stats::Busy.instance.size })
        end

        # Renders the sidebar's count badges.
        #
        # @return [Array] the Rack response
        def _badges
          badges = { jobs: API::Stats.enqueued, streams: visible_streams.size }
          badges[:crons] = API::Cron.instance.all.size if Config.scheduled.enabled
          badges[:batches] = API::Batch.kv.keys("*.meta", limit: nil).size
          ok render("overview/_badges", { badges: })
        end

        private

        # A process's threads, each the stream of the job it runs or nil while idle.
        def worker_cells(process, busy)
          streams = Array(busy[process[:identity]]).map { _1[:stream] }
          idle = [process[:concurrency].to_i - streams.size, 0].max
          streams + Array.new(idle)
        end

        def visible_streams
          API::Stream.all.reject { _1.name.start_with?("KV_", "_cosmo") }
        end
      end
    end
  end
end
