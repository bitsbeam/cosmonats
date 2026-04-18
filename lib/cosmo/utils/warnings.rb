# frozen_string_literal: true

module Cosmo
  module Utils
    module Warnings
      module_function

      def silence
        verbose = $VERBOSE
        $VERBOSE = nil
        yield
      ensure
        $VERBOSE = verbose
      end
    end
  end
end
