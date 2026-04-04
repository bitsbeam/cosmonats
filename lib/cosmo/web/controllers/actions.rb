# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Actions < Application
        def index
          content_for :title, "Actions"
          ok render("actions/index", layout: true)
        end
      end
    end
  end
end
