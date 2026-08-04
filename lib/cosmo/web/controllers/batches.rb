# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Batches < Application
        def index
          content_for :title, "Batches"
          ok render("batches/index", layout: true)
        end

        def _table
          limit = (params["limit"] || API::Batch::LIMIT).to_i
          ok render("batches/_table", { batches: API::Batch.all(limit:) })
        end
      end
    end
  end
end
