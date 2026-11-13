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
          ok render("batches/index", { query: query }, layout: true)
        end

        # Renders the batches panel: one page of batches and the links to its neighbours.
        #
        # @return [Array] the Rack response
        def _table
          limit = limit(API::Batch::LIMIT)
          page = API::Batch.page(before: cursor("before"), after: cursor("after"), limit:)
          ok render("batches/_table", { page:, query: query, cursor: { before: cursor("before"), after: cursor("after") }.compact })
        end

        private

        def query
          { limit: limit(API::Batch::LIMIT) }
        end

        def cursor(name)
          Integer(params[name], exception: false)&.positive? ? params[name].to_i : nil
        end
      end
    end
  end
end
