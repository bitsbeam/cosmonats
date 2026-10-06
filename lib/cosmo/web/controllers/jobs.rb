# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Jobs < Application
        def index
          content_for :title, "Jobs"
          processes_query = params.slice("page", "limit").transform_values(&:to_i).select { _2.positive? }
          ok render("jobs/index", { processes_query: }, layout: true)
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

        def delete_enqueued
          seq = path.split("/").last.to_i
          stream_name, = streams
          API::Stream.new(stream_name).delete(seq)
          _enqueued
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
          busy = API::Stats::Busy.instance
          total = busy.size
          page, limit, total_pages = paginate(total, API::Stats::Busy::LIMIT)
          polling = params["poll"].to_s != "0"
          ok render("jobs/_busy", { jobs: busy.list(page:, limit:), total:, page:, limit:, total_pages:, polling: })
        end

        def _processes
          processes = API::Stats::Processes.instance
          total = processes.size
          page, limit, total_pages = paginate(total, API::Stats::Processes::LIMIT)
          polling = params["poll"].to_s != "0"
          groups = processes.list(page:, limit:).chunk { API::Stats::Processes.kind(_1) }.to_a
          ok render("jobs/_processes", { groups:, total:, page:, limit:, total_pages:, polling: })
        end

        def _enqueued # rubocop:disable Metrics/AbcSize
          stream_name, stream_names = streams
          limit = (params["limit"] || API::Stream::LIMIT).to_i
          page = [params["page"].to_i, 1].max

          unless stream_name.to_s.empty?
            stream = API::Stream.new(stream_name)
            total = stream.total
            total_pages = (total.to_f / limit).ceil
            page = page.clamp(1, [total_pages, 1].max)
            jobs = stream.messages(page:, limit:)
          end

          ok render("jobs/_enqueued", { jobs:, total:, stream_name:, stream_names:, page:, limit:, total_pages: })
        end

        def _stats
          ok render("jobs/_stats", API::Stats.summary)
        end

        private

        def paginate(total, default_limit)
          limit = (params["limit"] || default_limit).to_i
          total_pages = (total.to_f / limit).ceil
          [params["page"].to_i.clamp(1, [total_pages, 1].max), limit, total_pages]
        end

        def streams
          stream_names = API::Stream.jobs.map(&:name)
          stream_name = params.fetch("stream_name", stream_names.first)
          [stream_name, stream_names]
        end
      end
    end
  end
end
