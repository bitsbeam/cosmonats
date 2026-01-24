# frozen_string_literal: true

RSpec.shared_context "Global helpers" do
  def client
    @client ||= Cosmo::Client.instance
  end

  def clean_streams
    client.list_streams.each { client.delete_stream(it) }
  rescue NATS::JetStream::Error::NotFound
    # nop
  end
end
