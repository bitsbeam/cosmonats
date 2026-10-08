# frozen_string_literal: true

module Cosmo
  module Job
    # The one path a job takes onto its stream, shared by {Job::ClassMethods#perform} and the ActiveJob adapter.
    module Enqueuer
      module_function

      # Publishes the job through {Config#client_middleware}.
      #
      # @param class_name [String]
      # @param args [Array]
      # @param options [Hash] job options, see {Data}
      # @param batch [Batch, nil] the batch the job joins; it is reserved a pending slot before the publish
      #   (see Batch#jobs) and released again when the publish fails or a middleware stops it, so the batch never
      #   waits on a lost job
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      # @raise [StreamNotFoundError] when the target stream does not exist
      # @raise [SchedulingDisabledError] for a delayed job while scheduling is turned off
      def enqueue(class_name, args, options, batch: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        options = options.merge(batch_id: batch.bid) if batch
        data = Data.new(class_name, args, options)
        raise SchedulingDisabledError if data.stream.to_s == Services::SCHEDULED && !Config.scheduled.enabled

        batch&.register_job!
        begin
          published = pipe(class_name, data)
        rescue StandardError
          batch&.rollback_job!
          raise
        end
        batch&.rollback_job! unless published
        data.jid if published
      end

      def pipe(class_name, data)
        payload = data.as_json
        published = false
        Config.client_middleware.invoke(class_name, payload, data.stream(target: true)) do
          publish(data, payload)
          published = true
        end
        published
      end

      def publish(data, payload)
        Client.instance.publish(data.subject, Utils::Json.dump(payload), stream: data.stream, header: data.headers)
      rescue NATS::JetStream::Error::NoStreamResponse
        raise StreamNotFoundError, data.stream.to_s
      end
    end
  end
end
