# frozen_string_literal: true

require "json"

module Cosmo
  module Stream
    class Data
      DEFAULTS = {
        batch_size: 100,
        consumer: {
          ack_policy: "explicit",
          max_deliver: 1,
          max_ack_pending: 3,
          ack_wait: 30,
          subjects: ["%{name}.>"]
        },
        publisher: { subject: "%{name}.default", serializer: nil }
      }.freeze
    end
  end
end
