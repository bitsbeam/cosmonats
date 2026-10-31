# frozen_string_literal: true

module Cosmo
  module API
    # Read-model over Cosmo::Batch's KV/counter state, for the status API and Web UI.
    class Batch
      LIMIT = 25

      # @param limit [Integer, nil] the most batches to return, nil for every one
      # @return [Array<Batch>]
      def self.all(limit: LIMIT)
        kv.keys("*.meta", limit: limit).map { |key| new(key.delete_suffix(".meta")) }
      end

      # Counts batches by direct gets, reading no further than +limit+.
      #
      # @param limit [Integer] the most batches to count
      # @return [Integer]
      def self.count(limit:)
        kv.direct_entries("*.meta", limit:).size
      end

      # @return [KV] the bucket holding each batch's meta, callbacks and finalized snapshot
      def self.kv
        Cosmo::Batch.kv
      end

      # @return [Cosmo::Batch::Counters] the per-batch total, pending and failed counters
      def self.counter
        Cosmo::Batch.counter
      end

      attr_reader :bid

      # @param bid [String] the batch id
      def initialize(bid)
        @bid = bid
      end

      # @return [Hash] the batch's stored metadata, empty when it has none
      def meta
        Utils::Json.parse(kv.get("#{bid}.meta")&.value) || {}
      end

      # @return [String, nil] the enclosing batch's id for a nested batch
      def parent_id
        meta[:parent_id]
      end

      # @return [Integer, nil]
      def created_at
        meta[:created_at]
      end

      # Whether the batch has been finalized.
      #
      # @return [Boolean]
      def ready?
        !!kv.get("#{bid}.ready")
      end

      # { total:, pending:, succeeded:, failed: } -- read from the +ready+
      # snapshot once finalized (counters are reset by then), or live off the
      # counters (with +pending+ still moving) while the batch is still open.
      #
      # @return [Hash]
      def stats
        entry = kv.get("#{bid}.ready")
        return Utils::Json.parse(entry.value).merge(pending: 0) if entry

        live_stats
      end

      # @param event [Symbol] +:success+ or +:complete+
      # @return [Hash, nil] the callback registered for +event+
      def callback(event)
        entry = kv.get("#{bid}.callback.#{event}")
        Utils::Json.parse(entry&.value)
      end

      # @return [Hash{Symbol => Hash, nil}] the +:success+ and +:complete+ callbacks
      def callbacks
        { success: callback(:success), complete: callback(:complete) }
      end

      # @param event [Symbol] +:success+ or +:complete+
      # @return [Boolean] whether the callback for +event+ has already fired
      def fired?(event)
        !!kv.get("#{bid}.fired.#{event}")
      end

      private

      def live_stats
        total = counter.get("#{bid}.total")
        failed = counter.get("#{bid}.failed")
        pending = counter.get("#{bid}.pending")
        { total: total, pending: pending, succeeded: total - failed - pending, failed: failed }
      end

      def kv
        self.class.kv
      end

      def counter
        self.class.counter
      end
    end
  end
end
