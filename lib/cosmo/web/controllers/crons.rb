# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Crons < Application
        def index
          content_for :title, "Crons"
          ok render("crons/index", layout: true)
        end

        def _table
          ok render("crons/_table", { schedules: cron.all })
        end

        # Dispatch the job immediately, bypassing the schedule timer.
        # Expects params["subject"] = the schedule subject stored in NATS.
        def run_now
          subject = Rack::Utils.unescape(params["subject"].to_s)
          cron.run_now!(subject)
          ok
        end

        # Purge the schedule from NATS so it stops firing.
        def delete
          subject = Rack::Utils.unescape(params["subject"].to_s)
          cron.delete!(subject)
          _table
        end

        private

        def cron
          @cron ||= API::Cron.instance
        end
      end
    end
  end
end
