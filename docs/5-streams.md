# Streams

```ruby
class ClicksProcessor
  include Cosmo::Stream

  options(
    stream: :clickstream,
    batch_size: 100,
    start_position: :last,  # :first, :last, :new, or timestamp
    consumer: {
      ack_policy: "explicit",
      max_deliver: 3,
      max_ack_pending: 100,
      subjects: ["events.clicks.>"]
    }
  )

  # Process one message at a time
  def process_one
    Analytics.track_click(message.data)
    message.ack
  end

  # OR process a batch
  def process(messages)
    Analytics.bulk_track(messages.map(&:data))
    messages.each(&:ack)
  end
end

# Publishing
ClicksProcessor.publish({ user_id: 123, page: "/home" }, subject: "events.clicks.homepage")

# Acknowledgment strategies
message.ack                          # Success
message.nack(delay: 5_000_000_000)   # Retry in 5 seconds (nanoseconds)
message.term                         # Permanent failure, no retry
```
