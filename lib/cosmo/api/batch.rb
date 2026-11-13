# frozen_string_literal: true

module Cosmo
  module API
    # Read-model over Cosmo::Batch's KV/counter state, for the status API and Web UI.
    class Batch
      LIMIT = 25
      META = "*.meta"

      # A slice of batches, newest first, with the cursors that lead to its neighbours (nil when there is none).
      Page = Struct.new(:batches, :newer, :older)

      # One page of batches, newest first. Batch ids are random, so key order says nothing about age; the bucket
      # keeps writes in creation order, so pages are cursors over its sequences (see {KV#direct_before}) and only a
      # page's metas are read.
      #
      # @param before [Integer, nil] the +older+ cursor of the page above: show the batches written before it
      # @param after [Integer, nil] the +newer+ cursor of the page below: show the batches written after it
      # @param limit [Integer] batches per page
      # @return [Page]
      def self.page(before: nil, after: nil, limit: LIMIT)
        entries = after ? kv.direct_after(META, after:, limit:) : kv.direct_before(META, before:, limit:)
        return Page.new([], nil, nil) if entries.empty?

        newest = entries.first.last
        oldest = entries.last.last
        Page.new(entries.map { |key, _| new(key.delete_suffix(".meta")) }, (newest if newer?(newest)), (oldest if older?(oldest)))
      end

      # @param newest [Integer] the sequence of a page's newest batch
      # @return [Boolean] whether a batch was created after it
      def self.newer?(newest)
        kv.direct_count(META, since: newest + 1).positive?
      end

      # @param oldest [Integer] the sequence of a page's oldest batch
      # @return [Boolean] whether a batch was created before it
      def self.older?(oldest)
        kv.direct_count(META) > kv.direct_count(META, since: oldest)
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
