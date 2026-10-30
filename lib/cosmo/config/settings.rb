# frozen_string_literal: true

module Cosmo
  class Config < ::Hash
    # +config.services+ in Cosmo.configure: +num_replicas+ for Cosmo's own streams and KV buckets, e.g. 3 on a NATS
    # cluster. Streams in cosmo.yml set their own +num_replicas+.
    Services = Struct.new(:num_replicas, keyword_init: true)

    # +config.scheduled+ in Cosmo.configure. Turned off, Cosmo neither creates the scheduled stream nor runs the
    # scheduler, and delayed jobs (+perform_in+/+perform_at+) and crons raise {SchedulingDisabledError}.
    Scheduled = Struct.new(:enabled, keyword_init: true)

    # +config.dead+ in Cosmo.configure: the dead-letter stream's retention (+max_age+ in seconds or a duration such as
    # "7d"). Turned off, a job that gives up is dropped instead of parked.
    Dead = Struct.new(:enabled, :max_age, :max_msgs, :max_bytes, keyword_init: true)

    # +config.batches+ in Cosmo.configure: how long a batch's tracking data lives (seconds or a duration such as "3d").
    Batches = Struct.new(:expiry, keyword_init: true)

    # +config.metrics+ in Cosmo.configure: per-day job metrics behind the web UI's Metrics tab, kept for +retention+
    # (seconds or a duration such as "30d"). Turned off, nothing is recorded and the tab is hidden.
    Metrics = Struct.new(:enabled, :retention, keyword_init: true)

    # +config.in_progress+ in Cosmo.configure: while enabled, every job or stream batch still being processed is
    # reported to NATS as in progress every {Heartbeat::INTERVAL} seconds, restarting its +ack_wait+, so it is not
    # redelivered to another worker while this one is still on it. Turned off, work running longer than its
    # consumer's +ack_wait+ is redelivered and may run twice at once.
    InProgress = Struct.new(:enabled, keyword_init: true)
  end
end
