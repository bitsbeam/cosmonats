# frozen_string_literal: true

module Cosmo
  class Web
    module Renderer
      ASSETS_ROOT = File.expand_path("assets", __dir__).freeze
      VIEWS_ROOT  = File.expand_path("views",  __dir__).freeze

      @templates = {}
      @lock = Mutex.new

      # Compiles a view into a Context method on its first render, so later renders skip reading and parsing it.
      #
      # @param path [String] the view, relative to VIEWS_ROOT and without +.erb+, e.g. +"jobs/_busy"+
      # @return [String] the name of the Context method that renders it
      def self.template(path)
        @lock.synchronize do
          @templates[path] ||= "template#{@templates.size}".tap do |name|
            source = File.read(File.join(VIEWS_ROOT, "#{path}.erb"))
            ERB.new(source, trim_mode: "-").def_method(Context, name, "#{path}.erb")
          end
        end
      end

      def redirect_to(url, status = 302)
        [status, { "location" => url_for(url) }, []]
      end

      def serve(filename, content_type, headers = nil)
        path = File.join(ASSETS_ROOT, filename)
        return not_found unless File.exist?(path)

        respond_with 200, body: File.binread(path), headers: { "content-type" => content_type }.merge(headers || {})
      end

      def ok(body = "")
        headers = { "content-type" => "text/html; charset=utf-8" }
        respond_with 200, body:, headers:
      end

      def no_content
        respond_with 204, body: ""
      end

      def not_found
        body = "<div class=\"empty\"><b>404</b>Not found</div>"
        headers = { "content-type" => "text/html; charset=utf-8" }
        respond_with 404, body:, headers:
      end

      # Prepend the mount prefix to an internal route.
      #   url_for("/jobs")  # => "/admin/cosmo/jobs"  (mounted)
      #   url_for("/jobs")  # => "/jobs"              (standalone)
      def url_for(path, params = nil)
        url = "#{@request.script_name}#{path}"
        url = "#{url}?#{params.to_a.map { _1.join("=") }.join("&")}" if params
        url
      end

      private

      def respond_with(status, headers: nil, body: "")
        [status, Hash(headers), [body]]
      end

      def erb(path, locals, content_for = nil)
        Context.new(locals, content_for).public_send(Renderer.template(path))
      end
    end
  end
end
