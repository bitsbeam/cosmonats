# frozen_string_literal: true

require "stringio"

module Cosmo
  class HTTPServer
    # Minimal WEBrick servlet adapting requests to a Rack app.
    class Handler < ::WEBrick::HTTPServlet::AbstractServlet
      def initialize(server, app)
        super(server)
        @app = app
      end

      def service(req, res)
        status, headers, body = @app.call(env_for(req))
        res.status = status
        write_headers(res, headers)
        body.each { res.body << _1 }
      ensure
        body.close if body.respond_to?(:close)
      end

      private

      def env_for(req)
        env = req.meta_vars.compact
        env.merge!(
          Rack::SCRIPT_NAME => "",
          Rack::PATH_INFO => req.path,
          Rack::QUERY_STRING => req.query_string.to_s,
          Rack::RACK_INPUT => StringIO.new(req.body.to_s).tap(&:binmode),
          Rack::RACK_ERRORS => $stderr,
          Rack::RACK_URL_SCHEME => req.ssl? ? "https" : "http"
        )
      end

      def write_headers(res, headers)
        headers.each do |key, value|
          key.downcase == "set-cookie" ? Array(value).each { res.cookies << _1 } : res[key] = Array(value).join(", ")
        end
      end
    end
  end
end
