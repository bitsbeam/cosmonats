# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Processes < Application
        def index
          return ok(table) if hx_request?

          content_for :title, "Processes"
          content_for :subtitle, "Every worker process heartbeating into NATS."
          ok render("processes/index", { table: table }, layout: true)
        end

        private

        def table # rubocop:disable Metrics/AbcSize
          processes = API::Stats::Processes.instance
          total = processes.size
          limit = (params["limit"] || API::Stats::Processes::LIMIT).to_i
          total_pages = (total.to_f / limit).ceil
          page = params["page"].to_i.clamp(1, [total_pages, 1].max)
          polling = params["poll"].to_s != "0"
          groups = processes.list(page:, limit:).chunk { API::Stats::Processes.kind(_1) }.to_a
          render("processes/_table", { groups:, total:, page:, limit:, total_pages:, polling:,
                                       query: { limit:, poll: (0 unless polling) }.compact })
        end
      end
    end
  end
end
