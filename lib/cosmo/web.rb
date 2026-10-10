# frozen_string_literal: true

require "rack"
require "json"
require "erb"
require "zlib"
require "cosmo/web/context"
require "cosmo/web/renderer"
require "cosmo/web/controllers/application"
require "cosmo/web/controllers/overview"
require "cosmo/web/controllers/jobs"
require "cosmo/web/controllers/processes"
require "cosmo/web/controllers/streams"
require "cosmo/web/controllers/crons"
require "cosmo/web/controllers/batches"
require "cosmo/web/controllers/metrics"

module Cosmo
  class Web
    include Renderer

    FONT_HEADERS = { "cache-control" => "public, max-age=31536000, immutable" }.freeze

    def self.call(env)
      new.call(env)
    end

    def call(env) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      @request = Rack::Request.new(env)
      path     = @request.path_info
      method   = @request.request_method

      response = case [method.downcase.to_sym, path]
                 in [:get,    "/" | ""]                 then [Controllers::Overview,  :index]
                 in [:get,    "/_kpis"]                 then [Controllers::Overview,  :_kpis]
                 in [:get,    "/_throughput"]           then [Controllers::Overview,  :_throughput]
                 in [:get,    "/_workers"]              then [Controllers::Overview,  :_workers]
                 in [:get,    "/_running"]              then [Controllers::Overview,  :_running]
                 in [:get,    "/_badges"]               then [Controllers::Overview,  :_badges]
                 in [:get,    "/jobs"]                  then [Controllers::Jobs,      :index]
                 in [:get,    "/jobs/busy"]             then [Controllers::Jobs,      :busy]
                 in [:get,    "/jobs/enqueued"]         then [Controllers::Jobs,      :enqueued]
                 in [:get,    "/jobs/scheduled"]        then [Controllers::Jobs,      :scheduled]
                 in [:get,    "/jobs/dead"]             then [Controllers::Jobs,      :dead]
                 in [:get,    "/jobs/_queues"]          then [Controllers::Jobs,      :_queues]
                 in [:patch,  %r{/jobs/retry/\d+}]      then [Controllers::Jobs,      :retry]
                 in [:delete, %r{/jobs/delete/\d+}]     then [Controllers::Jobs,      :delete]
                 in [:delete, %r{/jobs/enqueued/\d+}]   then [Controllers::Jobs,      :delete_enqueued]
                 in [:get,    "/processes"]             then [Controllers::Processes, :index]
                 in [:get,    "/streams"]               then [Controllers::Streams,   :index]
                 in [:get,    "/streams/info"]          then [Controllers::Streams,   :info]
                 in [:patch,  "/streams/pause"]         then [Controllers::Streams,   :pause]
                 in [:patch,  "/streams/unpause"]       then [Controllers::Streams,   :unpause]
                 in [:get,    "/crons"]                 then [Controllers::Crons,     :index]
                 in [:get,    "/crons/_table"]          then [Controllers::Crons,     :_table]
                 in [:delete, "/crons/delete"]          then [Controllers::Crons,     :delete]
                 in [:post,   "/crons/run"]             then [Controllers::Crons,     :run_now]
                 in [:get,    "/metrics"]               then [Controllers::Metrics,   :index]
                 in [:get,    "/metrics/_panel"]        then [Controllers::Metrics,   :_panel]
                 in [:get,    "/batches"]               then [Controllers::Batches,   :index]
                 in [:get,    "/batches/_table"]        then [Controllers::Batches,   :_table]
                 in [:get,    "/assets/htmx.min.js.gz"] then serve("htmx.2.0.8.min.js.gz",
                                                                   "application/javascript",
                                                                   { "content-encoding" => "gzip" })
                 in [:get, "/assets/app.css"]              then serve("app.css", "text/css")
                 in [:get, "/assets/app.js"]               then serve("app.js", "application/javascript")
                 in [:get, "/assets/logo.svg"]             then serve("logo.svg", "image/svg+xml")
                 in [:get, "/assets/fonts/geist.woff2"]    then serve("fonts/geist.woff2", "font/woff2", FONT_HEADERS)
                 in [:get, "/assets/fonts/geist-mono.woff2"] then serve("fonts/geist-mono.woff2", "font/woff2", FONT_HEADERS)
                 in [:get, "/favicon.ico"] then redirect_to("/assets/logo.svg", 301)
                 else not_found
                 end
      handler(response)
    end

    private

    def handler(response)
      if response[0].is_a?(Class)
        controller, action = response
        return controller.new(@request).send(action)
      end

      response
    end
  end
end
