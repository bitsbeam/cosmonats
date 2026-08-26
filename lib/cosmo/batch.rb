# frozen_string_literal: true

require "securerandom"
require "cosmo/batch/callback"
require "cosmo/batch/dispatcher"

module Cosmo
  # Groups jobs together and runs a callback once they've all finished.
  #
  #   batch = Cosmo::Batch.new
  #   batch.jobs { MyJob.perform_async(1); MyJob.perform_async(2) }
  #   batch.on(:complete, MyCallback, user_id: 1)
  #
  # :complete fires once every job is done, pass or fail.
  # :success only fires if none of them ended up dead-lettered or dropped.
  #
  # The callback is a plain Ruby class, not a job. It just needs an
  # on_complete/on_success(status, options) method:
  #
  #   class MyCallback
  #     def on_complete(status, options)
  #       Notifier.notify(options[:user_id], "#{status[:succeeded]}/#{status[:total]} done")
  #     end
  #   end
  #
  # It still runs on the worker pool, not on the thread that finished the
  # batch - it's wrapped in an internal Batch::Callback job.
  #
  #   status - { bid:, total:, succeeded:, failed: }
  #   options - arbitrary custom arguments passed to #on
  #
  # Only jobs enqueued inside a #jobs block count. Nested batches must be created explicitly,
  # by passing the parent's batch_id:
  #
  #   Cosmo::Batch.new(parent: batch_id)
  #
  # A nested batch counts as one job of its parent. If anything fails in it,
  # the failure is propagated to the parent counter either. The parent succeeds
  # when everything succeeds. Always call #jobs at least once, even with nothing
  # in it - a batch that never gets a #jobs call never closes and never fires.
  #
  # You can pass your own bid instead of letting one be generated - useful
  # when something else (e.g. an ActiveRecord id) needs to match it:
  #
  #   Cosmo::Batch.new(bid: your_id)
  #
  # Same meaning as a plain #new either way - it's still a fresh batch.
  #
  # == How this is actually stored in NATS
  #
  # Every batch has an id (bid, a random hex string). State lives
  # in two places, both keyed by that bid:
  #
  # 1. Three atomic counters (via API::Counter, namespace "batch", backed by
  #    the shared _cosmostats stream):
  #
  #      <bid>.total    - how many jobs have ever joined this batch
  #      <bid>.pending  - how many of them are still running
  #      <bid>.failed   - how many ended up dead-lettered or dropped
  #
  #    Each increment/decrement is one atomic NATS publish, and the reply
  #    tells you the resulting value right away - no separate read needed.
  #    Whichever decrement of +pending+ happens to bring it down to exactly
  #    0 is the one that finalizes the batch (see #release_pending). Since
  #    it's a single atomic counter, exactly one decrement can ever be "the
  #    one that hits zero", so the batch can't finish twice or too early.
  #
  # 2. A KV bucket (BUCKET, ttl'd so old batches clean themselves up):
  #
  #      <bid>.meta               - { parent_id, created_at }, written once at creation
  #      <bid>.callback.success   - { class, opts } from #on(:success, ...)
  #      <bid>.callback.complete  - { class, opts } from #on(:complete, ...)
  #      <bid>.ready              - { total, succeeded, failed }, written once
  #                                  by #finalize, right after reading the counters
  #      <bid>.fired.success      - exists once the :success callback has run
  #      <bid>.fired.complete     - exists once the :complete callback has run
  #      <bid>.finalized          - exists once #finalize has run for this bid
  #
  #    The fired.* and finalized keys are write-once: kv.create raises if the
  #    key already exists. That's what stops the same callback (or the same
  #    finalize) from running twice when two things race to trigger it - a
  #    job finishing at the same moment someone calls #on, for example.
  class Batch
    extend Dispatcher

    BUCKET = "cosmo_jobs_batches"
    DEFAULT_EXPIRY = "3d"
    EVENTS = %i[success complete].freeze

    def self.current
      Thread.current[:cosmo_batch]
    end

    # Called by Job::Processor when a job is done for good - acked, or
    # dead-lettered/dropped. Never call this for a retry. JID is used to dedupe: if the same
    # job's ack gets lost, and it's redelivered, we don't want to count it twice.
    def self.notify(bid, jid, success:)
      counter.increment("#{bid}.failed", msg_id: "batch.#{bid}.#{jid}.failed") unless success
      release_pending(bid, msg_id: "batch.#{bid}.#{jid}.pending")
    end

    def self.counter
      @counter ||= API::Counter.new("batch")
    end

    def self.kv
      @kv ||= API::KV.new(BUCKET, ttl: Utils::Duration.parse(Config[:batch_expiry] || DEFAULT_EXPIRY))
    end

    attr_reader :bid, :parent_id

    def initialize(bid: nil, parent: nil)
      @bid = bid || SecureRandom.hex(8)
      @parent_id = parent
      kv.set("#{@bid}.meta", Utils::Json.dump({ parent_id: @parent_id, created_at: Time.now.to_i }))
      link(@parent_id) if @parent_id
    end

    # Every perform_async/perform_at/perform_in called inside this block
    # joins the batch. Holds a placeholder "pending" slot for the whole
    # block, so the batch can't finish while you're still adding jobs, even
    # if the first one completes instantly. The placeholder never counts
    # toward total, so it doesn't skew the stats. Safe to call more than
    # once. If the block raises, we still release the placeholder (so the
    # batch isn't stuck) and let the error propagate as normal.
    def jobs
      previous = Thread.current[:cosmo_batch]
      Thread.current[:cosmo_batch] = self
      counter.increment("#{bid}.pending")
      begin
        yield
      ensure
        Thread.current[:cosmo_batch] = previous
        release_pending
      end
    end

    # Registers a callback for +event+ (:success or :complete). Can be
    # called before or after #jobs - if the batch already finished, it
    # fires right away.
    def on(event, klass, **opts)
      raise ArgumentError, "event must be :success or :complete" unless EVENTS.include?(event)

      kv.set("#{bid}.callback.#{event}", Utils::Json.dump({ class: klass.name, opts: opts }))
      try_fire(event)
    end

    # Called by Job#perform for each job added inside #jobs.
    def register_job!
      counter.increment("#{bid}.total")
      counter.increment("#{bid}.pending")
    end

    # Undoes #register_job! when the publish itself failed, so the job
    # never really joined the batch. Unlike a real completion, this also
    # reverts total, not just pending.
    def rollback_job!
      counter.decrement("#{bid}.total")
      release_pending
    end

    private

    # Bridges instance methods to the private class methods Dispatcher adds to Batch
    def counter = self.class.counter
    def kv = self.class.kv
    def link(parent_id) = self.class.send(:link, parent_id)
    def release_pending = self.class.send(:release_pending, bid)
    def try_fire(event) = self.class.send(:try_fire, bid, event)
  end
end
