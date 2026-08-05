# frozen_string_literal: true

RSpec.shared_context "Global helpers" do
  def client
    @client ||= Cosmo::Client.instance
  end

  def stream_size(name)
    Cosmo::API::Stream.new(name.to_s).size
  end

  def cleanup_state
    Results.instance.clear
    Cosmo::Config.internal[:streams] = []
    Cosmo::API::Busy.instance_variable_set(:@instance, nil)
    Cosmo::API::Counter.instance_variable_set(:@instance, nil)
    Cosmo::Publisher.instance_variable_set(:@instance, nil)
    Cosmo::Job::Limit.instance_variable_set(:@instance, nil)
    Cosmo::Batch.instance_variable_set(:@counter, nil)
    Cosmo::Batch.instance_variable_set(:@kv, nil)
  end

  def wait_until(timeout:)
    result = nil
    scale = ENV.fetch("COSMO_TEST_TIMEOUT_SCALE", ENV["CI"] ? 3 : 1).to_f
    deadline = Time.now + (timeout * scale)

    loop do
      result = yield
      return if result
      break if Time.now > deadline

      sleep 0.05
    end

    expect(result).to be_truthy
  end

  private

  def destroy_streams
    client.list_streams.each { client.delete_stream(_1.dig("config", "name")) }
  rescue NATS::JetStream::Error::NotFound
    # nop
  end

  def create_streams(configs)
    configs.each do |name, config|
      client.create_stream(name.to_s, config.except(:description))
    end
  end
end
