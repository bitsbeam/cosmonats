# frozen_string_literal: true

require "zlib"

module Cosmo
  module Job
    # Lanes split a job stream between several consumers, each filtering its own subjects, that workers poll in turn,
    # so a long run of jobs on one lane doesn't hold back the jobs on the others. They are set per stream with
    # +lanes+ in +consumers.jobs+, and a job's lane is part of its subject: +jobs.<stream>.lane-<n>.<class>+.
    module Lane
      module_function

      # @param stream [String, Symbol]
      # @return [Integer, nil] the stream's number of lanes, nil when it has none
      def count(stream)
        Config.dig(:consumers, :jobs, stream.to_sym, :lanes)
      end

      # @param stream [String, Symbol]
      # @param key [Object] an Integer is the lane itself (modulo the count), anything else is hashed into one
      # @return [Integer, nil] the job's lane, nil on a stream without lanes
      def pick(stream, key)
        lanes = count(stream) or return

        (key.is_a?(Integer) ? key : Zlib.crc32(key.to_s)) % lanes
      end

      # @param stream [String, Symbol]
      # @param job_name [String] the underscored job class name
      # @param key [Object] see {.pick}
      # @return [String] +jobs.<stream>.lane-<n>.<job_name>+, or +jobs.<stream>.<job_name>+ on a stream without lanes
      def subject(stream, job_name, key)
        lane = pick(stream, key)
        lane ? "jobs.#{stream}.#{name(lane)}.#{job_name}" : "jobs.#{stream}.#{job_name}"
      end

      # Puts a lane into a plain +jobs.<stream>.<job_name>+ subject, such as a cron firing's, when it is dispatched.
      # A subject that already has a lane, or is a custom one, is kept as it is.
      #
      # @param stream [String, Symbol]
      # @param subject [String]
      # @param key [Object] see {.pick}
      # @return [String]
      def route(stream, subject, key)
        job_name = subject.delete_prefix("jobs.#{stream}.")
        return subject if job_name == subject || job_name.include?(".")

        subject(stream, job_name, key)
      end

      # @param stream [String, Symbol]
      # @param lane [Integer]
      # @return [String] the subject filter of the lane's consumer
      def filter(stream, lane)
        "jobs.#{stream}.#{name(lane)}.>"
      end

      # @param lane [Integer]
      # @return [String] e.g. +lane-0+
      def name(lane)
        "lane-#{lane}"
      end
    end
  end
end
