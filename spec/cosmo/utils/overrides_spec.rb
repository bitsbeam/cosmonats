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

  # A second, distinct upstream bug lived in the same method: the post-wait timeout check
  # used to fire even when the pop right above it had just grabbed a real, already-delivered
  # message, discarding it for good (it's already removed from @pending_queue, so it's gone,
  # not merely delayed). In practice this needs the wait to return a message right as elapsed
  # time is perceived to have crossed the deadline -- a real race that's rare to hit through
  # actual thread timing in a fast local test, so we force the exact condition deterministically
  # instead of hoping to get lucky: fake MonotonicTime.since (only as observed by the thread
  # running #fetch) into reporting the deadline already blown, then deliver a real message
  # during the wait and confirm it's still returned rather than discarded. This is
  # Cosmo::Job::Processor's steady state (idle worker threads polling one empty stream) when a
  # scheduled/perform_at job comes due. See lib/cosmo/utils/overrides.rb.
  it "returns a message fetched right as the deadline is perceived to have already passed" do
    subscription = client.subscribe(subject, consumer, ack_policy: "explicit")

    allow(NATS::MonotonicTime).to receive(:since).and_wrap_original do |original, arg|
      Thread.current[:fake_deadline_blown] ? 1_000 : original.call(arg)
    end

    publisher = Thread.new do
      sleep 0.05
      client.publish(subject, "late-but-real")
    end

    Thread.current[:fake_deadline_blown] = true
    messages = subscription.fetch(1, timeout: 0.2)
    Thread.current[:fake_deadline_blown] = false
    publisher.join

    expect(messages.map(&:data)).to eq(["late-but-real"])
  end
end
