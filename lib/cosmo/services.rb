# frozen_string_literal: true

module Cosmo
  # The streams Cosmo itself depends on. They are built from the settings in Cosmo.configure, never from cosmo.yml,
  # and `cosmo --setup` creates them next to the user's streams.
  module Services
    SCHEDULED = Job::StreamFilter::SCHEDULED.to_s
    DEAD = "dead"
    METADATA = { "_cosmo.type" => "jobs" }.freeze
    RETENTION_CHANGE = 10_052

    module_function

    # Holds delayed jobs and every cron template. It alone enables NATS message scheduling, since a schedule can only
    # target a subject its own stream covers, and NATS refuses +discard: new+ wherever scheduling is enabled.
    #
    # @return [Hash, nil] nil when scheduling is turned off
    def scheduled_stream
      return unless Config.scheduled.enabled

      { storage: "file", retention: "workqueue", discard: "old", allow_direct: true, allow_msg_schedules: true,
        duplicate_window: Config.to_ns(120), subjects: ["jobs.#{SCHEDULED}.>", "#{API::Cron::Entry::SUBJECT_PREFIX}.>"],
        num_replicas: Config.replicas, description: "Scheduled jobs and cron schedules", metadata: METADATA }
    end

    # +max_deliver+ stays above 1: the scheduler naks a message that is not yet due, and one whose dispatch failed,
    # and both need another delivery.
    #
    # @return [Hash, nil] nil when scheduling is turned off
    def scheduled_consumer
      return unless Config.scheduled.enabled

      { ack_policy: "explicit", max_deliver: 5, max_ack_pending: 100, ack_wait: 10, subject: "jobs.#{SCHEDULED}.>" }
    end

    # @return [Hash, nil] nil when dead-lettering is turned off
    def dead_stream
      dead = Config.dead
      return unless dead.enabled

      { storage: "file", retention: "workqueue", discard: "old", allow_direct: true, duplicate_window: Config.to_ns(120),
        max_age: Config.to_ns(Utils::Duration.parse(dead.max_age)), max_msgs: dead.max_msgs, max_bytes: dead.max_bytes,
        subjects: ["jobs.#{DEAD}.>"], num_replicas: Config.replicas, description: "Dead jobs", metadata: METADATA }
    end

    # Creates or updates every enabled service stream, plus the internal stats counters.
    #
    # @return [Array<String>] the names of the service streams set up, without the internal counters
    def setup!
      streams = { SCHEDULED => scheduled_stream, DEAD => dead_stream }.compact
      streams.each { |name, config| setup_stream(name, config) }
      API::Counter.setup!
      streams.keys
    end

    # @raise [Error] when an existing stream has another retention policy, which NATS can't change in place
    def setup_stream(name, config)
      Client.instance.setup_stream(name, config)
    rescue NATS::JetStream::Error::APIError => e
      raise unless e.err_code == RETENTION_CHANGE

      raise Error, "The existing `#{name}` stream has another retention policy, which NATS can't change in place: " \
                   "delete it (`nats stream rm #{name}`, dropping its messages) and rerun `cosmo --setup`"
    end
  end
end
