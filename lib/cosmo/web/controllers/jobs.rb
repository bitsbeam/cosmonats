# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Jobs < Application
        # What an underscored class name can be inside a subject, with no wildcard or token separator to widen a purge.
        CLASS_TOKEN = /\A[a-z0-9_-]+\z/

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

        # Enqueues a scheduled job now: sends it to the stream that runs it and drops its schedule.
        #
        # @return [Array] the Rack response
        def run_scheduled
          return not_found unless Config.scheduled.enabled

          seq = path.split("/").last.to_i
          API::Stream.new("scheduled").retry(seq)
          ok panel("scheduled") + flash("Scheduled job ##{seq} enqueued now")
        end

        # Deletes a scheduled job, so it never runs. A cron schedule is not one: only the Crons tab removes those.
        #
        # @return [Array] the Rack response
        def delete_scheduled
          return not_found unless Config.scheduled.enabled

          seq = path.split("/").last.to_i
          stream = API::Stream.new("scheduled")
          stream.delete(seq) if stream.message(seq)
          ok panel("scheduled") + flash("Scheduled job ##{seq} deleted")
        end

        # Purges the delayed jobs of one class (+class+, its underscored name) or, without it, every delayed job.
        # Cron schedules and jobs already fired into +jobs.scheduled+ are not touched.
        #
        # @return [Array] the Rack response
        def purge_scheduled
          return not_found unless Config.scheduled.enabled

          name = params["class"].to_s
          return not_found unless name.empty? || name.match?(CLASS_TOKEN)

          filter = [Job::Data::SUBJECT_PREFIX, name.empty? ? nil : name, ">"].compact.join(".")
          purged = Client.instance.purge("scheduled", filter)
          scope = name.empty? ? "" : " #{name}"
          ok panel("scheduled") + flash("Purged #{purged} scheduled#{scope} #{purged == 1 ? "job" : "jobs"}")
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
          total = API::Stats.busy
          page, limit, total_pages = paginate(total, API::Registry::LIMIT)
          polling = params["poll"].to_s != "0"
          longest = params["order"] == "longest"
          jobs = API::Stats.running_page(page:, limit:, longest:)
          { jobs:, total:, page:, limit:, total_pages:, polling:,
            query: { limit:, poll: (0 unless polling), order: ("longest" if longest) }.compact }
        end

        def enqueued_locals # rubocop:disable Metrics/AbcSize
          stream_name, stream_sizes = streams
          limit = limit(API::Stream::LIMIT)
          after = params["after"].to_s[/\A\d+\z/]&.to_i
          locals = { stream_name:, stream_sizes:, page: 1, limit:, total: 0, total_pages: 0, jobs: nil, polling: false,
                     after:, next_after: nil, query: { stream_name: Rack::Utils.escape(stream_name.to_s), limit: } }
          return locals if stream_name.to_s.empty?

          stream = API::Stream.new(stream_name)
          total = stream_sizes.fetch(stream_name) { stream.total }
          jobs = stream.messages(limit: limit + 1, after: after || 0)
          next_after = jobs[limit - 1].seq.to_i if jobs.size > limit
          locals.merge(total:, jobs: jobs.first(limit), next_after:)
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
          limit = limit(default_limit)
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
