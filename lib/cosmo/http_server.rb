# frozen_string_literal: true

begin
  require "rack"
  require "rackup/handler/webrick"
  require "webrick"
rescue LoadError => e
  raise LoadError, "Cosmo::HTTPServer requires `rack`, `rackup` and `webrick` gems, add them to your Gemfile (#{e.message})"
end
require "json"
require "cosmo/http_server/health"

module Cosmo
  # WEBrick server running the Rack app in a background thread.
  class HTTPServer
    DEFAULT_HOST = "0.0.0.0"
    NOT_FOUND = [404, { "content-type" => "application/json" }, ['{"error":"not found"}']].freeze

    # Routing is done by middlewares, anything unmatched falls through to 404.
    def self.app
      Rack::Builder.app do
        use Health
        run ->(_env) { NOT_FOUND }
      end
    end

    def initialize(app = self.class.app, port:, host: DEFAULT_HOST)
      @app = app
      @host = host
      @port = port
    end

    def start
      @server = ::WEBrick::HTTPServer.new(
        BindAddress: @host,
        Port: @port,
        Logger: ::WEBrick::Log.new(IO::NULL),
        AccessLog: []
      )
      @server.mount("/", ::Rackup::Handler::WEBrick, @app)
      @thread = Thread.new { @server.start }
      Logger.info "HTTP server listening on #{@host}:#{port}"
      self
    end

    def stop
      return unless @server

      @server.shutdown
      @thread&.join
      @server = @thread = nil
    end

    # Actual bound port, useful when started with port 0.
    def port
      @server ? @server.listeners.first.addr[1] : @port
    end
  end
end
