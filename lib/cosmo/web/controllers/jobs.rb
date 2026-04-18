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

        def busy
          return _busy if hx_request?

          content_for :title, "Busy Jobs"
          ok render("jobs/busy", layout: true)
        end

        def enqueued
          return _enqueued if hx_request?

          content_for :title, "Enqueued Jobs"
          stream_name, _stream_names = streams
          ok render("jobs/enqueued", { stream_name: }, layout: true)
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
          seq = path.split("/").last.to_i
          stream = API::Stream.new("dead")
          stream.retry(seq)
          ok
        end

        def delete
          seq = path.split("/").last.to_i
          stream = API::Stream.new("dead")
          stream.delete(seq)
          ok
        end

        def _scheduled
          stream = API::Stream.new("scheduled")
          jobs = stream.messages(page: params["page"], limit: params["limit"])
          ok render("jobs/_scheduled", { jobs: jobs, total: stream.total })
        end

        def _dead
          stream = API::Stream.new("dead")
          jobs = stream.messages(page: params["page"], limit: params["limit"])
          ok render("jobs/_dead", { jobs: jobs, total: stream.total })
        end

        def _busy
          limit = (limit || 25).to_i
          jobs  = API::Busy.instance.list(limit:)
          ok render("jobs/_busy", { jobs: jobs, total: API::Busy.instance.size })
        end

        def _enqueued
          stream_name, stream_names = streams
          stream = API::Stream.new(stream_name)
          jobs = stream.messages(page: params["page"], limit: params["limit"])

          ok render("jobs/_enqueued", { jobs:, total: stream.total, stream_name:, stream_names: })
        end

        def _stats
          ok render("jobs/_stats", API::Stats.summary)
        end

        private

        def streams
          stream_names = API::Stream.jobs.map(&:name)
          stream_name = params.fetch("stream_name", stream_names.first)
          [stream_name, stream_names]
        end
      end
    end
  end
end
