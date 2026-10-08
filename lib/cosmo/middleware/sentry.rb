# frozen_string_literal: true

# rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize
module Cosmo
  module Middleware
    # Wraps every job execution in a Sentry transaction. Errors reach Sentry through {ERROR_HANDLER}, which also
    # captures those outside jobs (stream batches, fetches, the scheduler). Needs +sentry-ruby+, so it is not loaded
    # by default:
    #
    #   require "cosmo/middleware/sentry"
    #
    #   Cosmo.configure do |config|
    #     config.server_middleware { |chain| chain.add Cosmo::Middleware::Sentry }
    #     config.error_handlers << Cosmo::Middleware::Sentry::ERROR_HANDLER
    #   end
    class Sentry
      NAME_PREFIX = "Cosmonats"
      OP_NAME = "queue.cosmonats"
      SPAN_ORIGIN = "auto.queue.cosmonats"
      STATUS_OK = 200
      STATUS_FAIL = 500

      ERROR_HANDLER = lambda do |error, context|
        next unless ::Sentry.initialized?

        ::Sentry.capture_exception(error, contexts: { cosmonats: context }, hint: { background: true, integration: "cosmonats" })
      end

      # @param job [Cosmo::Job]
      # @param data [Hash]
      # @param message [NATS::Msg]
      def call(job, data, message)
        return yield unless ::Sentry.initialized?

        scope = ::Sentry.get_current_scope
        transaction_name = "#{NAME_PREFIX}/#{job.class.name}"
        scope.set_transaction_name(transaction_name, source: :task)
        transaction = ::Sentry.start_transaction(
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: OP_NAME,
          origin: SPAN_ORIGIN
        )
        transaction&.set_data("messaging.message.id", data[:jid])
        transaction&.set_data("messaging.destination.name", "#{message.metadata.stream}:#{message.subject}")
        transaction&.set_data("messaging.message.retry.count", data[:retry] || 0)

        begin
          result = yield
          transaction&.set_http_status(STATUS_OK)
          transaction&.finish
          result
        rescue StandardError
          transaction&.set_http_status(STATUS_FAIL)
          transaction&.finish
          raise
        end
      end
    end
  end
end
