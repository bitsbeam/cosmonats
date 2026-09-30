# frozen_string_literal: true

module Cosmo
  class Batch
    # The actual job that gets enqueued when a batch finishes. It looks up
    # the plain Ruby class you passed to Batch#on and calls on_success or
    # on_complete on it.
    class Callback
      include Cosmo::Job

      def perform(class_name, event, status, opts)
        klass = Utils::String.safe_constantize(class_name)
        klass&.new&.public_send("on_#{event}", status, opts)
      end
    end
  end
end
