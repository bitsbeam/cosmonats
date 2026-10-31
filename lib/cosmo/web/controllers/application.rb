# frozen_string_literal: true

module Cosmo
  class Web
    module Controllers
      class Application
        include Renderer

        MAX_LIMIT = 100

        # @param request [Rack::Request]
        def initialize(request)
          @request = request
        end

        # Captures content the layout renders, such as the page title.
        #
        # @param name [Symbol]
        # @param content [String]
        # @return [String] the content
        def content_for(name, content)
          @content_for ||= {}
          @content_for[name] = content
        end

        # @param template [String] the view, relative to Renderer::VIEWS_ROOT and without +.erb+
        # @param locals [Hash{Symbol => Object}, nil] the view's instance variables
        # @param layout [Boolean] whether to wrap the view in the page layout
        # @return [String] the rendered HTML
        def render(template, locals = nil, layout: false)
          defaults = { request: @request }
          locals = Hash(locals).merge(defaults)
          view = erb(template, locals)
          return view unless layout

          @content_for ||= {}
          @content_for[:view] = view
          erb("layout", defaults, @content_for)
        end

        # @return [Hash{String => Object}] the query and form parameters
        def params
          @request.params
        end

        # @param default [Integer] the page size when the request names none
        # @return [Integer] the requested page size, kept between 1 and MAX_LIMIT
        def limit(default)
          (params["limit"] || default).to_i.clamp(1, MAX_LIMIT)
        end

        # @return [String] the request path
        def path
          @request.path
        end

        # @return [Boolean] whether htmx sent the request
        def hx_request?
          @request.get_header("HTTP_HX_REQUEST") == "true"
        end

        # 503 while NATS is unreachable: a bare body for an htmx request, which leaves the page as it is and backs
        # off, or a page that reloads itself.
        #
        # @return [Array] the Rack response
        def unavailable
          headers = { "content-type" => "text/html; charset=utf-8", "retry-after" => Circuit::OPEN_FOR.to_s }
          return respond_with(503, headers:, body: "NATS is unreachable") if hx_request?

          content_for :title, "Unavailable"
          content_for :subtitle, "The web UI can't reach NATS."
          respond_with 503, headers:, body: render("shared/unavailable", { retry: Circuit::OPEN_FOR }, layout: true)
        end

        # An out-of-band swap of the page header's flash message, appended to an htmx response.
        #
        # @param message [String] escaped before rendering
        # @return [String] the HTML
        def flash(message)
          %(<div id="flash" class="flash" hx-swap-oob="true">#{Rack::Utils.escape_html(message)}</div>)
        end
      end
    end
  end
end
