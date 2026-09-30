# frozen_string_literal: true

module Cosmo
  module API
    # Read-model over Cosmo::Batch's KV/counter state, for the status API and Web UI.
    class Batch
      LIMIT = 25

      def self.all(limit: LIMIT)
        kv.keys("*.meta", limit: limit).map { |key| new(key.delete_suffix(".meta")) }
      end

      def self.kv
        Cosmo::Batch.kv
      end

      def self.counter
        Cosmo::Batch.counter
      end

      attr_reader :bid

      def initialize(bid)
        @bid = bid
      end

      def meta
        Utils::Json.parse(kv.get("#{bid}.meta")&.value) || {}
      end

      def parent_id
        meta[:parent_id]
      end

      def created_at
        meta[:created_at]
      end

      def ready?
        !!kv.get("#{bid}.ready")
      end

      # { total:, pending:, succeeded:, failed: } -- read from the +ready+
      # snapshot once finalized (counters are reset by then), or live off the
      # counters (with +pending+ still moving) while the batch is still open.
      def stats
        entry = kv.get("#{bid}.ready")
        return Utils::Json.parse(entry.value).merge(pending: 0) if entry

        live_stats
      end

      def callback(event)
        entry = kv.get("#{bid}.callback.#{event}")
        Utils::Json.parse(entry&.value)
      end

      def callbacks
        { success: callback(:success), complete: callback(:complete) }
      end

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
