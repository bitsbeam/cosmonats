# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # The +_cosmostats+ counters: job totals ({Totals}) and batch progress (+Batch.counter+). Always on, since the web
      # UI's dashboard and batches depend on them.
      class Counters < Counter
        STREAM_NAME = "_cosmostats"
        DESCRIPTION = "Cosmo statistics"
      end
    end
  end
end
