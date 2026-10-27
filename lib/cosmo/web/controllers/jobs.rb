# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Jobs < Application
        # Renders the jobs page on the busy tab.
        #
        # @return [Array] the Rack response
        def index
          tab("busy")
        end

        # Renders the busy tab.
        #
        # @return [Array] the Rack response
        def busy
          tab("busy")
        end

        # Renders the enqueued tab.
        #
        # @return [Array] the Rack response
        def enqueued
          tab("enqueued")
        end

        # Renders the scheduled tab, or 404 while scheduling is disabled.
        #
        # @return [Array] the Rack response
        def scheduled
          return not_found unless Config.scheduled.enabled

          tab("scheduled")
        end

        # Renders the dead tab, or 404 while the dead stream is disabled.
        #
        # @return [Array] the Rack response
        def dead
          return not_found unless Config.dead.enabled

          tab("dead")
        end

        # Renders the queues table.
        #
        # @return [Array] the Rack response
        def _queues
          ok render("jobs/_queues", { queues: API::Stats.queues, compact: params["compact"].to_s == "1" })
        end

        # Sends a dead job back to its queue.
        #
        # @return [Array] the Rack response
        def retry
          return not_found unless Config.dead.enabled

          seq = path.split("/").last.to_i
          API::Stream.new("dead").retry(seq)
          ok flash("Dead job ##{seq} sent back to its queue")
        end

        # Deletes a dead job.
        #
        # @return [Array] the Rack response
        def delete
          return not_found unless Config.dead.enabled

          seq = path.split("/").last.to_i
          API::Stream.new("dead").delete(seq)
          ok flash("Dead job ##{seq} deleted")
        end

        # Removes an enqueued message from its stream and renders the enqueued tab.
        #
        # @return [Array] the Rack response
        def delete_enqueued
          seq = path.split("/").last.to_i
          stream_name = params["stream_name"]
          API::Stream.new(stream_name).delete(seq)
          ok panel("enqueued") + flash("Message ##{seq} removed from #{stream_name}")
        end

        private

        def tab(name)
          return ok(panel(name)) if hx_request?

          content_for :title, "Jobs"
          content_for :subtitle, "Queues, in-flight work and everything waiting its turn."
          ok render("jobs/index", { panel: panel(name) }, layout: true)
        end

        def panel(name)
          render("jobs/_panel", send("#{name}_locals").merge(tab: name, counts: counts))
        end

        def counts
          counts = { busy: API::Stats.busy, enqueued: API::Stats.enqueued }
          counts[:scheduled] = API::Stats.scheduled if Config.scheduled.enabled
          counts[:dead] = API::Stats.dead if Config.dead.enabled
          counts
        end

        def busy_locals
          busy = API::Stats::Busy.instance
          total = busy.size
          page, limit, total_pages = paginate(total, API::Stats::Busy::LIMIT)
          polling = params["poll"].to_s != "0"
          { jobs: busy.list(page:, limit:), total:, page:, limit:, total_pages:, polling:, query: { limit:, poll: (0 unless polling) }.compact }
        end

        def enqueued_locals # rubocop:disable Metrics/AbcSize
          stream_name, stream_sizes = streams
          limit = (params["limit"] || API::Stream::LIMIT).to_i
          page = [params["page"].to_i, 1].max
          locals = { stream_name:, stream_sizes:, page:, limit:, total: 0, total_pages: 0, jobs: nil, polling: false,
                     query: { stream_name: Rack::Utils.escape(stream_name.to_s), limit: } }
          return locals if stream_name.to_s.empty?

          stream = API::Stream.new(stream_name)
          total = stream_sizes.fetch(stream_name) { stream.total }
          total_pages = (total.to_f / limit).ceil
          page = page.clamp(1, [total_pages, 1].max)
          locals.merge(total:, total_pages:, page:, jobs: stream.messages(page:, limit:))
        end

        def scheduled_locals
          stored_locals("scheduled").merge(polling: true)
        end

        def dead_locals
          stored_locals("dead", order: :desc).merge(polling: false)
        end

        def stored_locals(name, order: :asc)
          stream = API::Stream.new(name)
          total = stream.total
          page, limit, total_pages = paginate(total, API::Stream::LIMIT)
          { jobs: stream.messages(page:, limit:, order:), total:, page:, limit:, total_pages:, query: { limit: } }
        end

        def paginate(total, default_limit)
          limit = (params["limit"] || default_limit).to_i
          total_pages = (total.to_f / limit).ceil
          [params["page"].to_i.clamp(1, [total_pages, 1].max), limit, total_pages]
        end

        def streams
          stream_sizes = API::Stream.jobs.to_h { [_1.name, _1.size] }
          stream_name = params.fetch("stream_name") { stream_sizes.find { |_, size| size.positive? }&.first || stream_sizes.keys.first }
          [stream_name, stream_sizes]
        end
      end
    end
  end
end
