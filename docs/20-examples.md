# Examples

**Email queue with scheduling:**
```ruby
class EmailJob
  include Cosmo::Job
  options stream: :default, retry: 3

  def perform(user_id, template)
    user = User.find(user_id)
    EmailService.send(user.email, template)
  end
end

EmailJob.perform_async(123, "welcome")
EmailJob.perform_in(1.day, 123, "followup")
```

**Image Processing Pipeline:**
```ruby
class ImageProcessor
  include Cosmo::Stream
  options(
    stream: :images,
    consumer: { subjects: ["images.uploaded.>"] }
  )

  def process_one
    processed = ImageService.process(message.data["url"])
    publish(processed, subject: "images.processed.optimized")
    message.ack
  rescue => e
    logger.error "Processing failed: #{e.message}"
    message.nack(delay: 30_000_000_000) # retry in 30s
  end
end

ImageProcessor.publish({ url: "https://example.com/image.jpg" }, subject: "images.uploaded.user")
```

**Real-Time Analytics:**
```ruby
class AnalyticsAggregator
  include Cosmo::Stream
  options batch_size: 1000, consumer: { subjects: ["events.*.>"] }

  def process(messages)
    aggregates = messages.map(&:data).group_by { |e| e["type"] }.transform_values(&:count)
    Analytics.bulk_insert(aggregates)
    messages.each(&:ack)
  end
end
```
