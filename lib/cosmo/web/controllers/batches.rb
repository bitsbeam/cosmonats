# frozen_string_literal: true

require "cosmo/web/controllers/application"

module Cosmo
  class Web
    module Controllers
      class Batches < Application
        # Renders the batches page.
        #
        # @return [Array] the Rack response
        def index
          content_for :title, "Batches"
          content_for :subtitle, "Grouped jobs with a callback when the last one lands."
          ok render("batches/index", layout: true)
        end

        # Renders the batches table.
        #
        # @return [Array] the Rack response
        def _table
          limit = (params["limit"] || API::Batch::LIMIT).to_i
          ok render("batches/_table", { batches: API::Batch.all(limit:) })
        end
      end
    end
  end
end
