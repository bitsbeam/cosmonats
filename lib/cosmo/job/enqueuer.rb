# frozen_string_literal: true

module Cosmo
  module Job
    # The one path a job takes onto its stream, shared by {Job::ClassMethods#perform} and the ActiveJob adapter.
    module Enqueuer
      module_function

      # @param class_name [String]
      # @param args [Array]
      # @param options [Hash] job options, see {Data}
      # @param batch [Batch, nil] the batch the job joins; it is reserved a pending slot before the publish
      #   (see Batch#jobs) and released again when the publish fails, so the batch never waits on a lost job
      # @return [String] the job's jid
      # @raise [StreamNotFoundError] when the target stream does not exist
      # @raise [SchedulingDisabledError] for a delayed job while scheduling is turned off
      def enqueue(class_name, args, options, batch: nil)
        options = options.merge(batch_id: batch.bid) if batch
        data = Data.new(class_name, args, options)
        raise SchedulingDisabledError if data.stream.to_s == Services::SCHEDULED && !Config.scheduled.enabled

        batch&.register_job!
        begin
          publish(data)
        rescue StandardError
          batch&.rollback_job!
          raise
        end
        data.jid
      end

      def publish(data)
        Client.instance.publish(data.subject, data.to_json, stream: data.stream, header: data.headers)
      rescue NATS::JetStream::Error::NoStreamResponse
        raise StreamNotFoundError, data.stream.to_s
      end
    end
  end
end
