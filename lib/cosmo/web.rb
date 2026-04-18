# frozen_string_literal: true

require "rack"
require "json"
require "erb"
require "cosmo/web/context"
require "cosmo/web/renderer"
require "cosmo/web/controllers/application"
require "cosmo/web/controllers/jobs"
require "cosmo/web/controllers/streams"
require "cosmo/web/controllers/actions"

module Cosmo
  class Web
    include Renderer

    def self.call(env)
      new.call(env)
    end

    def call(env) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      @request = Rack::Request.new(env)
      path     = @request.path_info
      method   = @request.request_method

      response = case [method.downcase.to_sym, path]
                 in [:get,    "/"]                      then redirect_to("/jobs")
                 in [:get,    "/jobs"]                  then [Controllers::Jobs,    :index]
                 in [:get,    "/jobs/scheduled"]        then [Controllers::Jobs,    :scheduled]
                 in [:get,    "/jobs/dead"]             then [Controllers::Jobs,    :dead]
                 in [:get,    "/jobs/busy"]             then [Controllers::Jobs,    :busy]
                 in [:get,    "/jobs/enqueued"]         then [Controllers::Jobs,    :enqueued]
                 in [:patch,  %r{/jobs/retry/\d+}]      then [Controllers::Jobs,    :retry]
                 in [:delete, %r{/jobs/delete/\d+}]     then [Controllers::Jobs,    :delete]
                 in [:get,    "/jobs/_stats"]           then [Controllers::Jobs,    :_stats]
                 in [:get,    "/jobs/_scheduled"]       then [Controllers::Jobs,    :_scheduled]
                 in [:get,    "/jobs/_dead"]            then [Controllers::Jobs,    :_dead]
                 in [:get,    "/jobs/_busy"]            then [Controllers::Jobs,    :_busy]
                 in [:get,    "/jobs/_enqueued"]        then [Controllers::Jobs,    :_enqueued]
                 in [:get,    "/streams"]               then [Controllers::Streams, :index]
                 in [:get,    "/streams/info"]          then [Controllers::Streams, :info]
                 in [:get,    "/streams/_table"]        then [Controllers::Streams, :_table]
                 in [:get,    "/streams/_info"]         then [Controllers::Streams, :_info]
                 in [:get,    "/actions"]               then [Controllers::Actions, :index]
                 in [:get,    "/assets/htmx.min.js.gz"] then serve("htmx.2.0.8.min.js.gz",
                                                                   "application/javascript",
                                                                   { "content-encoding" => "gzip" })
                 in [:get, "/assets/app.css"]         then serve("app.css", "text/css")
                 in [:get, "/favicon.ico"]            then no_content
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
