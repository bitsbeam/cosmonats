# frozen_string_literal: true

module Cosmo
  class Batch
    # The engine behind Batch.notify: decides when a batch is done and
    # fires its callbacks.
    module Dispatcher
      private

      # Decrements pending. If this decrement just brought it to zero,
      # finalize the batch. This never touches total or failed - that's what
      # lets #jobs release its placeholder slot without messing up the stats
      # we report back.
      def release_pending(bid, msg_id: nil)
        pending = counter.decrement("#{bid}.pending", msg_id: msg_id)
        finalize(bid) if pending.to_i.zero?
      end

      # Runs once per batch. Has its own "already done" guard, separate from
      # try_fire's, because calling #jobs again on an already-finished batch
      # would otherwise re-run this and double-report to the parent batch.
      def finalize(bid)
        kv.create("#{bid}.finalized", "1")

        total = counter.get("#{bid}.total")
        failed = counter.get("#{bid}.failed")
        stats = { total: total, succeeded: total - failed, failed: failed }
        kv.set("#{bid}.ready", Utils::Json.dump(stats))
        purge_counters(bid)

        EVENTS.each { |event| try_fire(bid, event, stats: stats) }
        parent_propagate(bid, failed: failed)
      rescue NATS::KeyValue::KeyWrongLastSequenceError
        # already finalized - this is a stray completion from a reused Batch, ignore it
      end

      def purge_counters(bid)
        %w[total pending failed].each { |key| counter.purge("#{bid}.#{key}") }
      end

      # Tells the parent batch "one of your jobs (me) is done", counting any
      # failure in this batch as one failure for the parent. Same shape as
      # #notify - the child's bid just stands in for a jid here.
      def parent_propagate(bid, failed:)
        meta = Utils::Json.parse(kv.get("#{bid}.meta")&.value)
        parent_id = meta && meta[:parent_id]
        return unless parent_id

        notify(parent_id, bid, success: failed.zero?)
      end

      # Adds this batch as one job of the parent batch.
      def link(parent_id)
        counter.increment("#{parent_id}.total")
        counter.increment("#{parent_id}.pending")
      end

      # Fires the callback for +event+, if one is registered and the batch is
      # ready. Safe to call any number of times from either #on or a job
      # finishing - it only actually fires once.
      def try_fire(bid, event, stats: nil)
        callback_entry = kv.get("#{bid}.callback.#{event}")
        stats ||= Utils::Json.parse(kv.get("#{bid}.ready")&.value)
        return unless fireable?(callback_entry, event, stats)

        kv.create("#{bid}.fired.#{event}", "1")
        dispatch_callback(callback_entry, bid, event, stats)
      rescue NATS::KeyValue::KeyWrongLastSequenceError
        # someone else already fired this event, do nothing
      end

      def fireable?(callback_entry, event, stats)
        return false unless callback_entry && stats
        return false if event == :success && stats[:failed].to_i.positive?

        true
      end

      def dispatch_callback(callback_entry, bid, event, stats)
        callback = Utils::Json.parse(callback_entry.value)
        status = stats.merge(bid: bid)
        Callback.perform_async(callback[:class], event, status, callback[:opts] || {})
      end
    end
  end
end
