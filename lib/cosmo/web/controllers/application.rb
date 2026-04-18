# frozen_string_literal: true

module Cosmo
  class Web
    module Controllers
      class Application
        include Renderer

        def initialize(request)
          @request = request
        end

        def content_for(name, content)
          @content_for ||= {}
          @content_for[name] = content
        end

        def render(template, locals = nil, layout: false)
          defaults = { request: @request }
          locals = Hash(locals).merge(defaults)
          view = erb(template, locals)
          return view unless layout

          @content_for ||= {}
          @content_for[:view] = view
          erb("layout", defaults, @content_for)
        end

        def params
          @request.params
        end

        def path
          @request.path
        end

        def hx_request?
          @request.get_header("HTTP_HX_REQUEST") == "true"
        end
      end
    end
  end
end
