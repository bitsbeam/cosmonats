# frozen_string_literal: true

require "cosmo/web/controllers/application"
require "cosmo/web/chart"

module Cosmo
  class Web
    module Controllers
      class Metrics < Application
        RANGES = { 1 => "Today", 7 => "7 days", 30 => "30 days" }.freeze

        def index
          return not_found unless Config.metrics.enabled

          content_for :title, "Metrics"
          ok render("metrics/index", { days:, ranges: RANGES }, layout: true)
        end

        # The chart and the table together, so the charted job stays highlighted across refreshes.
        def _panel
          return not_found unless Config.metrics.enabled

          rows = metrics.summary(days:)
          job = charted(rows)
          chart = Chart.new(metrics.daily(job, days:)) if job && days > 1
          ok render("metrics/_panel", { rows:, job:, days:, chart: })
        end

        private

        # The requested job while it has rows in the period, the busiest one otherwise.
        def charted(rows)
          job = params["job"].to_s
          rows.any? { _1[:job] == job } ? job : rows.first&.dig(:job)
        end

        def days
          value = params["days"].to_i
          RANGES.key?(value) ? value : 7
        end

        def metrics
          API::Stats::Metrics.instance
        end
      end
    end
  end
end
