# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Streams < Application
        def index
          return ok(list) if hx_request?

          content_for :title, "Streams"
          content_for :subtitle, "JetStream streams and the consumers reading them."
          ok render("streams/index", layout: true)
        end

        def info
          return ok(render("streams/_info", info_locals(API::Stream.new(name)))) if hx_request?

          content_for :title, "Streams"
          content_for :subtitle, "Configuration of #{name}."
          ok render("streams/info", { name: }, layout: true)
        end

        def pause
          stream = API::Stream.new(name)
          stream.pause!
          toggled(stream, "paused")
        end

        def unpause
          stream = API::Stream.new(name)
          stream.unpause!
          toggled(stream, "resumed")
        end

        private

        def name
          Rack::Utils.unescape(params["name"].to_s)
        end

        def list
          streams = API::Stream.all.reject { _1.name.start_with?("KV_", "_cosmo") }.map { card(_1) }
          render("streams/_list", { streams: })
        end

        def toggled(stream, verb)
          body = case params["view"] || (params["banner"] && "banner")
                 when "banner" then render("streams/_pause_banner", { name: stream.name, paused: stream.paused? })
                 when "queue" then render("jobs/_queue_row", { queue: API::Stats.queue(stream), compact: false })
                 else render("streams/_stream", { stream: card(stream) })
                 end
          ok body + flash("#{stream.name} #{verb}")
        end

        def card(stream)
          state, config = stream.info.values
          { name: stream.name, state:, config:, consumers: stream.consumers, paused: stream.paused? }
        end

        def info_locals(stream)
          stream.info.merge(name: stream.name, paused: stream.paused?)
        end
      end
    end
  end
end
