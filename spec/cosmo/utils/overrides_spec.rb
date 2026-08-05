# frozen_string_literal: true

require "securerandom"

RSpec.describe "NATS::JetStream::PullSubscription#fetch patch" do
  let(:uniq)     { SecureRandom.hex(4) }
  let(:stream)   { "overrides_spec_#{uniq}" }
  let(:consumer) { "overrides_spec_consumer_#{uniq}" }
  let(:subject)  { "overrides_spec.#{uniq}.msgs" }

  before do
    client.create_stream(stream, subjects: [subject], storage: "memory", retention: "workqueue")
  end

  after do
    client.delete_stream(stream)
  end

  # Upstream nats-pure 2.5.0 leaves `start_time` unassigned for a batch-of-1 fetch, so a
  # thread woken by another thread's signal on the same subscription (both sharing the
  # subscription's pending_queue/wait_for_msgs_cond) blows up with a bare TypeError instead
  # of a clean timeout/empty result. See lib/cosmo/utils/overrides.rb for the full writeup.
  it "does not raise when many threads fetch concurrently from the same, empty subscription" do
    subscription = client.subscribe(subject, consumer, ack_policy: "explicit")
    errors = Concurrent::Array.new

    threads = 6.times.map do
      Thread.new do
        20.times do
          subscription.fetch(1, timeout: 0.1)
        rescue NATS::Timeout
          # expected - stream is empty
        rescue StandardError => e
          errors << e
        end
      end
    end
    threads.each(&:join)

    expect(errors).to be_empty
  end

  it "delivers every published message exactly once to concurrent fetchers" do
    subscription = client.subscribe(subject, consumer, ack_policy: "explicit")
    total = 200
    total.times { |i| client.publish(subject, "msg-#{i}") }

    received = Concurrent::Array.new
    errors = Concurrent::Array.new

    threads = 6.times.map do
      Thread.new do
        loop do
          messages = subscription.fetch(1, timeout: 0.2)
          messages.each do |m|
            received << m.data
            m.ack
          end
        rescue NATS::Timeout
          break if received.size >= total
        rescue StandardError => e
          errors << e
          break
        end
      end
    end
    threads.each { |t| t.join(10) }

    expect(errors).to be_empty
    expect(received.size).to eq(total)
    expect(received.uniq.size).to eq(total)
  end
end
