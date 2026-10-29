# frozen_string_literal: true

module Cosmo
  module Job
    # The one path a job takes onto its stream, shared by {Job::ClassMethods#perform} and the ActiveJob adapter.
    module Enqueuer
      # Jobs published at once by {.enqueue_many}, before waiting for their acks.
      CHUNK_SIZE = 1_000

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
      def enqueue(class_name, args, options, batch: nil)
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

      # Enqueues one job per argument list, publishing them a chunk at a time with {Client#publish_many}. Each job
      # still runs through {Config#client_middleware}, whose block only marks it for publishing: the chunk is
      # published once every job in it went through the chain.
      #
      # @param class_name [String]
      # @param list [Array<Array>] each job's arguments
      # @param options [Hash] job options shared by every job, see {Data}
      # @param batch [Batch, nil] the batch the jobs join
      # @return [Array<String, nil>] each job's jid, nil for one a client middleware stopped
      # @raise [ArgumentError] when +list+ is not an array of argument arrays
      # @raise [BulkEnqueueError] when the stream refused jobs of a chunk; the chunks after it are not published
      # @raise [SchedulingDisabledError] for delayed jobs while scheduling is turned off
      def enqueue_many(class_name, list, options, batch: nil)
        raise ArgumentError, "expected an array of argument arrays" unless list.is_a?(::Array) && list.all?(::Array)

        options = options.merge(batch_id: batch.bid) if batch
        jids = []
        list.each_slice(CHUNK_SIZE) do |chunk|
          offset = jids.size
          chunk_jids, errors = publish_chunk(class_name, chunk, options, batch)
          jids.concat(chunk_jids)
          raise BulkEnqueueError.new(jids + Array.new(list.size - jids.size), errors.transform_keys { _1 + offset }) if errors.any?
        end
        jids
      end

      # @param class_name [String]
      # @param chunk [Array<Array>] each job's arguments
      # @param options [Hash]
      # @param batch [Batch, nil]
      # @return [Array(Array<String, nil>, Hash{Integer => StandardError})] each job's jid, and why the jobs the
      #   stream refused were not enqueued, by their index in +chunk+
      def publish_chunk(class_name, chunk, options, batch)
        jobs = chunk.map { |args| through_middleware(class_name, Data.new(class_name, args, options)) }
        published = jobs.compact
        return [jobs.map { nil }, {}] if published.empty?

        batch&.register_job!(published.size)
        results = publish_all(published, batch)
        batch&.rollback_job!(results.count { !_1.is_a?(NATS::JetStream::PubAck) })
        collect(jobs, results)
      end

      # @param class_name [String]
      # @param data [Data]
      # @return [Array(Data, Hash), nil] the job and the payload to publish, or nil when a client middleware stopped it
      def through_middleware(class_name, data)
        raise SchedulingDisabledError if data.stream.to_s == Services::SCHEDULED && !Config.scheduled.enabled

        payload = data.as_json
        job = nil
        Config.client_middleware.invoke(class_name, payload, data.stream(target: true)) { job = [data, payload] }
        job
      end

      # @param jobs [Array<Array(Data, Hash)>]
      # @param batch [Batch, nil] whose slots for every job are released when the publish raises
      # @return [Array<NATS::JetStream::PubAck, StandardError>]
      def publish_all(jobs, batch)
        messages = jobs.map do |(data, payload)|
          header = data.headers.merge(NATS::JetStream::Header::EXPECTED_STREAM => data.stream.to_s)
          { subject: data.subject, payload: Utils::Json.dump(payload), header: header }
        end
        Client.instance.publish_many(messages)
      rescue StandardError
        batch&.rollback_job!(jobs.size)
        raise
      end

      # @param jobs [Array<Array(Data, Hash), nil>] nil for a job a client middleware stopped
      # @param results [Array<NATS::JetStream::PubAck, StandardError>] one per published job
      # @return [Array(Array<String, nil>, Hash{Integer => StandardError})]
      def collect(jobs, results)
        results = results.each
        errors = {}
        jids = jobs.each_with_index.map do |job, index|
          next unless job

          result = results.next
          next job.first.jid if result.is_a?(NATS::JetStream::PubAck)

          errors[index] = result.is_a?(NATS::JetStream::Error::NoStreamResponse) ? StreamNotFoundError.new(job.first.stream.to_s) : result
          nil
        end
        [jids, errors]
      end

      # Runs the client middleware around the publish.
      #
      # @param class_name [String]
      # @param data [Data]
      # @return [Boolean] whether the job was published
      def pipe(class_name, data)
        payload = data.as_json
        published = false
        Config.client_middleware.invoke(class_name, payload, data.stream(target: true)) do
          publish(data, payload)
          published = true
        end
        published
      end

      # @param data [Data]
      # @param payload [Hash] the job's payload, possibly changed by a middleware
      # @return [NATS::JetStream::PubAck]
      # @raise [StreamNotFoundError] when the target stream does not exist
      def publish(data, payload)
        Client.instance.publish(data.subject, Utils::Json.dump(payload), stream: data.stream, header: data.headers)
      rescue NATS::JetStream::Error::NoStreamResponse
        raise StreamNotFoundError, data.stream.to_s
      end
    end
  end
end
