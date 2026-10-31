# frozen_string_literal: true

module Cosmo
  module API
    class KV
      LIMIT = 25

      attr_reader :kv

      # Opens the +name+ bucket, creating it with +options+ when it doesn't exist.
      #
      # @param name [String]
      # @param options [Hash, nil] bucket settings, see {Client#kv}
      def initialize(name, options = nil)
        @name = name
        @options = Hash(options)
        @kv = client.kv(@name, **@options)
      end

      # @param key [String, Integer]
      # @param value [#to_s]
      # @param ttl [Integer, nil] seconds before the key expires; with it the key is only created when absent
      # @return [Integer] the stored message's sequence
      # @raise [NATS::KeyValue::KeyWrongLastSequenceError] when +ttl+ is given and the key is live
      def set(key, value, ttl: nil)
        return kv.put(key, value.to_s) unless ttl

        # Pass ttl: (seconds) to set per-message expiry.
        # Raises `NATS::KeyValue::KeyWrongLastSequenceError` when the key is live.
        publish_cas(key, value.to_s, ttl, last_seq: 0).seq
      end

      # @param key [String, Integer]
      # @return [NATS::KeyValue::Entry, nil] nil when the key doesn't exist
      def get(key)
        kv.get(key)
      rescue NATS::KeyValue::KeyNotFoundError
        # nop
      end

      # Creates +key+ if it does not already exist -- a plain CAS-if-absent with
      # no per-message TTL involved. Raises NATS::KeyValue::KeyWrongLastSequenceError
      # when the key is already live, so callers can use it as a fire-once gate.
      #
      # @param key [String, Integer]
      # @param value [#to_s]
      # @return [Integer] the key's revision
      def create(key, value)
        kv.create(key, value.to_s)
      end

      # Writes a KV-Operation tombstone. On a ttl-bearing bucket this leaves the
      # subject occupied, so a subsequent #set(ttl:) CAS with last_seq: 0 will
      # keep failing -- use #erase on those buckets instead.
      #
      # @param key [String, Integer]
      # @return [Integer] the tombstone's sequence
      def delete(key)
        kv.delete(key)
      end

      # Walks the bucket and collects live keys. Pass +limit: nil+ to walk the whole
      # bucket -- a bounded +limit+ stops the watch early, so it can never be used
      # to count (see #count).
      #
      # @param subject [String, nil] a key filter, every key when nil
      # @param limit [Integer, nil]
      # @param offset [Integer] live keys to skip first
      # @return [Array<String>]
      def keys(subject = nil, limit: LIMIT, offset: 0)
        walk(subject, limit:, offset:, meta_only: true).map(&:first)
      end

      # Same walk as #keys, but carries each value back with its key. The watch
      # already has the values in hand, so callers that need them get one pass
      # instead of a #keys walk followed by a #get per key.
      # @param subject [String, nil] a key filter, every key when nil
      # @param limit [Integer, nil]
      # @param offset [Integer] live entries to skip first
      # @return [Array<Array(String, String)>] +[key, value]+ pairs
      def entries(subject = nil, limit: LIMIT, offset: 0)
        walk(subject, limit:, offset:, meta_only: false)
      end

      # Same pairs as #entries, read by batched direct gets instead of a watch: no consumer is created, any replica
      # can answer, and the cost doesn't grow with the writes landing on the bucket while it's read. Keys come in
      # the order they were last written. Turns on direct gets for the bucket first, see #direct!.
      #
      # @param subject [String, nil] a key filter, every key when nil
      # @param limit [Integer, nil] the most messages to read, tombstones included; nil for every one
      # @return [Array<Array(String, String)>] +[key, value]+ pairs
      def direct_entries(subject = nil, limit: nil)
        direct!
        messages = client.direct_messages("KV_#{@name}", "$KV.#{@name}.#{subject || ">"}", limit:)
        messages.filter_map do |msg|
          header = msg.header
          [header[NATS::JetStream::Header::SUBJECT].delete_prefix("$KV.#{@name}."), msg.data] unless header["KV-Operation"]
        end
      end

      # How many keys match +subject+, counted by the server without reading any value: one request however many
      # keys there are. Turns on direct gets for the bucket first, see #direct!.
      #
      # @param subject [String, nil] a key filter, every key when nil
      # @return [Integer]
      def direct_count(subject = nil)
        direct!
        client.count_messages("KV_#{@name}", "$KV.#{@name}.#{subject || ">"}")
      end

      # The sorted keys matching +subject+, without their values, for paging through a bucket in a stable order.
      # Turns on direct gets for the bucket first, see #direct!.
      #
      # @param subject [String, nil] a key filter, every key when nil
      # @return [Array<String>]
      def direct_keys(subject = nil)
        direct!
        client.subjects("KV_#{@name}", "$KV.#{@name}.#{subject || ">"}").map { _1.delete_prefix("$KV.#{@name}.") }
      end

      # The values of +keys+, in one batched direct get. NATS answers for at most 1024 keys at a time.
      #
      # @param keys [Array<String>]
      # @return [Hash{String => String}] the value by key, without the keys that don't exist
      def direct_values(keys)
        direct!
        messages = client.last_messages("KV_#{@name}", keys.map { "$KV.#{@name}.#{_1}" })
        messages.each_with_object({}) do |(subject, msg), values|
          values[subject.delete_prefix("$KV.#{@name}.")] = msg.data unless msg.header&.key?("KV-Operation")
        end
      end

      # Writes every pair before waiting for any ack, so a batch costs about one round trip instead of one each.
      #
      # @param pairs [Hash{String => #to_s}] the value by key
      # @return [void]
      # @raise [StandardError] the first error among the acks
      def write_many(pairs)
        acks = client.publish_many(pairs.map { |key, value| { subject: "$KV.#{@name}.#{key}", payload: value.to_s } })
        error = acks.find { _1.is_a?(StandardError) }
        raise error if error
      end

      # Turns on +allow_direct+ for a bucket created without it, as nats-pure creates them. Checked once per instance.
      #
      # @return [true]
      def direct!
        @direct ||= begin
          stream = "KV_#{@name}"
          config = client.stream_info(stream).config
          client.update_stream(stream, config.to_h.compact.except(:name).merge(allow_direct: true)) unless config.allow_direct
          true
        end
      end

      # Writes a KV-Operation tombstone (same issue as #delete on ttl buckets).
      #
      # @param key [String, Integer]
      # @return [NATS::JetStream::PubAck]
      def purge(key)
        kv.purge(key)
      end

      # Removes +key+ leaving no trace at all -- unlike #delete/#purge, which
      # write a KV-Operation tombstone message. Mirrors how per-message
      # Nats-TTL expiry removes a key, so callers never have to distinguish
      # "deleted" from "TTL-expired" on read.
      #
      # @param key [String, Integer]
      # @return [Integer, nil] the number of messages purged
      def erase(key)
        client.purge("KV_#{@name}", "$KV.#{@name}.#{key}")
      end

      # Removes every key in the bucket.
      #
      # @return [Integer, nil] the number of messages purged
      def clean
        client.purge("KV_#{@name}", ">")
      end

      # @return [Integer] the number of live keys
      def count
        keys(limit: nil).size
      rescue NATS::KeyValue::NoKeysFoundError, NATS::JetStream::Error::NotFound
        0
      end
      alias size count

      private

      def walk(subject, limit:, offset:, meta_only:)
        results = []
        skipped = 0
        seen = 0
        watcher = kv.watch(subject || ">", meta_only:)
        begin
          watcher.each do |entry|
            if entry.nil?
              break if drained?(watcher, seen)

              next
            end

            seen += 1
            unless entry.operation
              next skipped += 1 if skipped < offset.to_i

              results << [entry.key, entry.value]
              break if limit && results.size >= limit
            end
            break if entry.delta.zero?
          end
        ensure
          watcher.stop
        end
        results
      end

      # nats-pure ends the initial walk with a nil once consumer info reports nothing pending and
      # nothing received yet, but the server can answer that info before the pushed entries arrive.
      # The nil is only trustworthy when the consumer really delivered no more than was seen.
      # https://github.com/nats-io/nats-pure.rb/issues/197
      def drained?(watcher, seen)
        watcher._sub.consumer_info.delivered.consumer_seq <= seen
      end

      # CAS = Compare-And-Swap: publish +value+ with a per-message TTL of +ttl+ whole seconds (at least 1),
      # but only if the subject's current last sequence matches +last_seq+
      # (sent as the Nats-Expected-Last-Subject-Sequence header). Raises
      # NATS::KeyValue::KeyWrongLastSequenceError if it doesn't match --
      # e.g. last_seq: 0 means "only publish if nothing exists here yet".
      def publish_cas(key, value, ttl, last_seq:)
        headers = { NATS::JetStream::Header::EXPECTED_LAST_SUBJECT_SEQUENCE => last_seq.to_s }
        client.js.publish("$KV.#{@name}.#{key}", value, header: headers, ttl: [ttl.to_i, 1].max)
      rescue NATS::JetStream::Error::APIError => e
        raise NATS::KeyValue::KeyWrongLastSequenceError, e.description if e.err_code == 10_071

        raise
      end

      def client
        Client.instance
      end
    end
  end
end
