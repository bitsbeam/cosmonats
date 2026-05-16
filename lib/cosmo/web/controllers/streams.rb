# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Streams < Application
        def index
          return _table if hx_request?

          content_for :title, "Streams"
          ok render("streams/index", layout: true)
        end

        def info
          name = Rack::Utils.unescape(@request.params["name"])
          return _info if hx_request?

          content_for :title, "Streams"
          ok render("streams/info", { name: name }, layout: true)
        end

        def pause
          name = Rack::Utils.unescape(@request.params["name"])
          stream = API::Stream.new(name)
          stream.pause!
          return ok render("streams/_pause_banner", banner_locals(stream)) if @request.params["banner"]

          ok render("streams/_stream_row", { stream: row_locals(stream) })
        end

        def unpause
          name = Rack::Utils.unescape(@request.params["name"])
          stream = API::Stream.new(name)
          stream.unpause!
          return ok render("streams/_pause_banner", banner_locals(stream)) if @request.params["banner"]

          ok render("streams/_stream_row", { stream: row_locals(stream) })
        end

        def _table
          streams = API::Stream.all.map { row_locals(_1) }
          ok render("streams/_table", { streams: streams })
        end

        def _info
          name = Rack::Utils.unescape(@request.params["name"])
          stream = API::Stream.new(name)
          ok render("streams/_info", stream.info.merge(name:, paused: stream.paused?))
        end

        private

        def row_locals(stream)
          state, config = stream.info.values
          { name: stream.name, messages: state.messages, bytes: state.bytes,
            first_seq: state.first_seq, last_seq: state.last_seq,
            consumer_count: state.consumer_count,
            subjects: config.subjects,
            paused: stream.paused? }
        end

        def banner_locals(stream)
          { name: stream.name, paused: stream.paused? }
        end
      end
    end
  end
end
