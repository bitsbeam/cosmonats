# frozen_string_literal: true

require "forwardable"

module Cosmo
  module Utils
    # A thread pool that reuses a fixed number of threads operating off a fixed size queue.
    # At any point, at most `num_threads` will be active processing tasks. When all threads are busy new
    # tasks posted to the thread pool are blocked until a thread becomes available.
    # Should a thread crash for any reason the thread will immediately be removed
    # from the pool and replaced.
    class ThreadPool
      extend Forwardable

      delegate %i[shutdown wait_for_termination] => :@pool

      # @param concurrency [Integer] number of threads
      def initialize(concurrency)
        @mutex = Thread::Mutex.new
        @concurrency = concurrency
        @available = concurrency
        @cond = ConditionVariable.new
        @pool = Concurrent::FixedThreadPool.new(concurrency)
      end

      # Blocks until no task is running.
      #
      # @return [void]
      def wait_idle
        @mutex.synchronize { @cond.wait(@mutex) until @available == @concurrency }
      end

      # Runs the block on a pool thread, blocking until one is free.
      #
      # @yield the task
      # @return [void]
      def post
        @mutex.synchronize do
          @cond.wait(@mutex) while @available <= 0
          @available -= 1
        end

        @pool.post do
          yield
        ensure
          @mutex.synchronize do
            @available += 1
            @cond.signal
          end
        end
      end
    end
  end
end
