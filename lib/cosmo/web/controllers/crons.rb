# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Crons < Application
        def index
          return not_found unless Config.scheduled.enabled

          content_for :title, "Crons"
          content_for :subtitle, "Schedules parked in NATS. NATS keeps the time."
          ok render("crons/index", layout: true)
        end

        def _table
          return not_found unless Config.scheduled.enabled

          ok render("crons/_table", { schedules: cron.all })
        end

        # Dispatch the job immediately, bypassing the schedule timer.
        # Expects params["subject"] = the schedule subject stored in NATS.
        def run_now
          return not_found unless Config.scheduled.enabled

          subject = Rack::Utils.unescape(params["subject"].to_s)
          cron.run_now!(subject)
          ok flash("#{label(subject)} enqueued now")
        end

        # Purge the schedule from NATS so it stops firing.
        def delete
          return not_found unless Config.scheduled.enabled

          subject = Rack::Utils.unescape(params["subject"].to_s)
          cron.delete!(subject)
          ok render("crons/_table", { schedules: cron.all }) + flash("#{label(subject)} deleted")
        end

        private

        def cron
          @cron ||= API::Cron.instance
        end

        # "cosmo.cron.default.report_job.monthly" → "monthly", "cosmo.cron.default.report_job" → "report_job"
        def label(subject)
          parts = subject.split(".")
          parts.size > 4 ? parts.drop(4).join(".") : parts.last
        end
      end
    end
  end
end
