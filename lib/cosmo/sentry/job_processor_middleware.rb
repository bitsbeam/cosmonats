# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength
module Cosmo
  module Sentry
    module JobProcessorMiddleware
      NAME_PREFIX = "Cosmonats"
      OP_NAME = "queue.cosmonats"
      SPAN_ORIGIN = "auto.queue.cosmonats"
      STATUS_OK = 200
      STATUS_FAIL = 500

      # @param job_instance [Cosmo::Job]
      # @param data [Hash]
      # @param duration [Float, nil]
      def perform_job(job_instance, data:, duration: nil)
        unless ::Sentry.initialized?
          super
          return
        end

        scope = ::Sentry.get_current_scope
        transaction_name = "#{NAME_PREFIX}/#{job_instance.class.name}"
        scope.set_transaction_name(transaction_name, source: :task)

        transaction = ::Sentry.start_transaction(
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: OP_NAME,
          origin: SPAN_ORIGIN
        )

        begin
          super

          transaction&.set_http_status(STATUS_OK)
          transaction&.finish
        rescue StandardError => e
          ::Sentry.capture_exception(
            e,
            contexts: { cosmonats: data, duration: duration },
            hint: { background: true, integration: "cosmonats" }
          )
          transaction&.set_http_status(STATUS_FAIL)
          transaction&.finish

          raise e
        end
      end
    end
  end
end
# rubocop:enable Metrics/MethodLength
