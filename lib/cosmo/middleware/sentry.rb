# frozen_string_literal: true

# rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize
module Cosmo
  module Middleware
    # Wraps every job execution in a Sentry transaction and captures the exceptions it raises. Needs +sentry-ruby+,
    # so it is not loaded by default:
    #
    #   require "cosmo/middleware/sentry"
    #
    #   Cosmo.configure do |config|
    #     config.server_middleware { |chain| chain.add Cosmo::Middleware::Sentry }
    #   end
    class Sentry
      NAME_PREFIX = "Cosmonats"
      OP_NAME = "queue.cosmonats"
      SPAN_ORIGIN = "auto.queue.cosmonats"
      STATUS_OK = 200
      STATUS_FAIL = 500

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
        rescue StandardError => e
          ::Sentry.capture_exception(
            e,
            contexts: {
              cosmonats: data.merge(
                nats_stream: message.metadata.stream,
                nats_subject: message.subject,
                timeout_duration: job.class.default_options[:limit]&.dig(:duration)&.to_i
              )
            },
            hint: {
              background: true,
              integration: "cosmonats"
            }
          )
          transaction&.set_http_status(STATUS_FAIL)
          transaction&.finish
          raise e
        end
      end
    end
  end
end
