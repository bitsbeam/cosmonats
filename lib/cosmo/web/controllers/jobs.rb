# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Jobs < Application
        def index
          content_for :title, "Jobs"
          ok render("jobs/index", layout: true)
        end

        def scheduled
          return _scheduled if hx_request?

          content_for :title, "Scheduled Jobs"
          ok render("jobs/scheduled", layout: true)
        end

        def dead
          return _dead if hx_request?

          content_for :title, "Dead Jobs"
          ok render("jobs/dead", layout: true)
        end

        def retry
          stream_name = @request.params["stream"]
          seq = @request.params["seq"].to_i
          api.retry(stream_name, seq)

          no_content
        end

        def delete
          no_content
        end

        def _scheduled
          limit = @request.params["limit"]
          stats = api.scheduled(limit)
          ok render("jobs/_scheduled", stats)
        end

        def _dead
          limit = @request.params["limit"]
          stats = api.dead(limit)
          ok render("jobs/_dead", stats)
        end

        def _stats
          ok render("jobs/_stats", api.stats)
        end
      end
    end
  end
end
