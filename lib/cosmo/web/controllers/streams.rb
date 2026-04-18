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

        def _table
          streams = API::Stream.all.map do |stream|
            state, config = stream.info.values
            { name: stream.name, messages: state.messages, bytes: state.bytes,
              first_seq: state.first_seq, last_seq: state.last_seq,
              consumer_count: state.consumer_count,
              subjects: config.subjects }
          end

          ok render("streams/_table", { streams: streams })
        end

        def _info
          name = Rack::Utils.unescape(@request.params["name"])
          state = API::Stream.new(name).info.merge(name:)
          ok render("streams/_info", state)
        end
      end
    end
  end
end
