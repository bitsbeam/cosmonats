# frozen_string_literal: true

module Cosmo
  class HTTPServer
    # Rack middleware answering GET /ping with 200 and no checks, every other request goes down the stack.
    # Useful as a liveness probe: it only proves the process is up and serving HTTP.
    class Ping
      PATH = "/ping"
      HEADERS = { "content-type" => "text/plain", "cache-control" => "no-store" }.freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env[Rack::PATH_INFO] == PATH
        return [405, HEADERS.merge("allow" => "GET, HEAD"), []] unless %w[GET HEAD].include?(env[Rack::REQUEST_METHOD])

        [200, HEADERS.dup, ["pong"]]
      end
    end
  end
end
