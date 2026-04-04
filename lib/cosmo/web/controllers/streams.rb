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
          ok render("streams/_table", api.streams)
        end

        def _info
          name = Rack::Utils.unescape(@request.params["name"])
          ok render("streams/_info", api.info(name))
        end
      end
    end
  end
end
