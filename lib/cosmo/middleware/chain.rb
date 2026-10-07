# frozen_string_literal: true

module Cosmo
  module Middleware
    # An ordered list of middleware classes wrapped around job execution, outermost first.
    #
    # A middleware is any class whose instances respond to +call(job, data, message)+ and yield to run
    # the rest of the chain. Every invocation builds fresh instances, so a middleware may keep per-job
    # state in instance variables. Adding a class that is already in the chain moves it instead.
    #
    #   class Timing
    #     def initialize(threshold:) = @threshold = threshold
    #
    #     def call(job, data, message)
    #       yield
    #     end
    #   end
    #
    #   Cosmo.configure do |config|
    #     config.server_middleware { |с| с.add Timing, threshold: 5 }
    #   end
    class Chain
      include Enumerable

      Entry = Struct.new(:klass, :args, :kwargs) do
        def build
          klass.new(*args, **kwargs)
        end
      end

      # @yieldparam chain [Chain]
      def initialize
        @entries = []
        yield self if block_given?
      end

      # @yieldparam entry [Entry]
      def each(&)
        @entries.each(&)
      end

      # Appends +klass+, so it runs innermost, closest to the job.
      #
      # @param klass [Class]
      # @return [Chain]
      def add(klass, *args, **kwargs)
        remove(klass)
        @entries << Entry.new(klass, args, kwargs)
        self
      end

      # Inserts +klass+ first, so it runs outermost.
      #
      # @param klass [Class]
      # @return [Chain]
      def prepend(klass, *args, **kwargs)
        remove(klass)
        @entries.unshift(Entry.new(klass, args, kwargs))
        self
      end

      # Inserts +klass+ right before +existing+, or first when +existing+ is not in the chain.
      #
      # @param existing [Class]
      # @param klass [Class]
      # @return [Chain]
      def insert_before(existing, klass, *args, **kwargs)
        entry = take(klass, args, kwargs)
        @entries.insert(index(existing) || 0, entry)
        self
      end

      # Inserts +klass+ right after +existing+, or last when +existing+ is not in the chain.
      #
      # @param existing [Class]
      # @param klass [Class]
      # @return [Chain]
      def insert_after(existing, klass, *args, **kwargs)
        entry = take(klass, args, kwargs)
        position = index(existing)
        @entries.insert(position ? position + 1 : @entries.size, entry)
        self
      end

      # @param klass [Class]
      # @return [Chain]
      def remove(klass)
        @entries.delete_if { _1.klass == klass }
        self
      end

      # @param klass [Class]
      # @return [Boolean]
      def exists?(klass)
        @entries.any? { _1.klass == klass }
      end
      alias include? exists?

      # @return [Boolean]
      def empty?
        @entries.empty?
      end

      # @return [Chain]
      def clear
        @entries.clear
        self
      end

      # Runs the block wrapped in every middleware, passing +args+ to each one's +call+.
      #
      # @return [Object] the outermost middleware's return value, normally the block's
      def invoke(*args, &)
        return yield if empty?

        traverse(map(&:build), 0, args, &)
      end

      private

      def traverse(chain, position, args, &block)
        return yield if position >= chain.size

        chain[position].call(*args) { traverse(chain, position + 1, args, &block) }
      end

      def index(klass)
        @entries.index { _1.klass == klass }
      end

      def take(klass, args, kwargs)
        position = index(klass)
        position ? @entries.delete_at(position) : Entry.new(klass, args, kwargs)
      end
    end
  end
end
