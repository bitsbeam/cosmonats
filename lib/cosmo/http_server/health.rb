# frozen_string_literal: true

module Cosmo
  class HTTPServer
    # Rack middleware answering GET /health, every other request goes down the stack.
    # Responds 200 when the engine is running and NATS is connected, 503 otherwise.
    class Health
      PATH = "/health"
      HEADERS = { "content-type" => "application/json", "cache-control" => "no-store" }.freeze

      def initialize(app, check: nil)
        @app = app
        @check = check || method(:default_check)
      end

      def call(env)
        return @app.call(env) unless env[Rack::PATH_INFO] == PATH
        return [405, HEADERS.merge("allow" => "GET, HEAD"), []] unless %w[GET HEAD].include?(env[Rack::REQUEST_METHOD])

        checks = @check.call
        healthy = checks.values.all?
        body = Utils::Json.dump({ status: healthy ? "ok" : "unavailable", checks: checks })
        [healthy ? 200 : 503, HEADERS.dup, [body]]
      end

      private

      def default_check
        { engine: Engine.instance.running?, nats: nats_connected? }
      end

      def nats_connected?
        Client.instance.nc.connected?
      rescue StandardError
        false
      end
    end
  end
end
