# frozen_string_literal: true

RSpec.shared_context "Global helpers" do
  def client
    @client ||= Cosmo::Client.instance
  end

  def stream_size(name)
    Cosmo::API::Stream.new(name.to_s).size
  end

  def prepare_streams
    Cosmo::API::Busy.instance_variable_set(:@instance, nil)
    Cosmo::API::Counter.instance_variable_set(:@instance, nil)
    Cosmo::Publisher.instance_variable_set(:@instance, nil)

    # Keep the scheduler fetch timeout short so teardown isn't blocked by the default 5-second NATS pull window.
    ENV["COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT"] = "0.5"
    destroy_streams
    Results.instance.clear
    create_streams(Cosmo::Config.dig(:setup, :jobs))

    yield

    destroy_streams
    Results.instance.clear
    ENV.delete("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT")
  end

  def wait_until(timeout:)
    result = nil
    deadline = Time.now + timeout

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
    client.list_streams.each { client.delete_stream(_1) }
  rescue NATS::JetStream::Error::NotFound
    # nop
  end

  def create_streams(configs)
    configs.each do |name, config|
      client.create_stream(name.to_s, config.except(:description))
    rescue NATS::JetStream::Error::StreamNameAlreadyInUse
      nil # stream survived the destroy_streams call — that's fine
    end
  end
end
