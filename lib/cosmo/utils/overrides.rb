# frozen_string_literal: true

Cosmo::Utils::Warnings.silence do
  members = NATS::JetStream::API::StreamConfig.members + [:allow_msg_counter]
  NATS::JetStream::API::StreamConfig = Struct.new(*members, keyword_init: true) do
    def initialize(opts = {})
      rem = opts.keys - members
      opts.delete_if { |k| rem.include?(k) }
      super
    end
  end

  members = NATS::JetStream::PubAck.members + [:val]
  NATS::JetStream::PubAck = Struct.new(*members, keyword_init: true)
end
