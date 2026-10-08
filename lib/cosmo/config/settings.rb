# frozen_string_literal: true

module Cosmo
  class Config < ::Hash
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
  end
end
