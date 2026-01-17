<div align="center">

# 🚀 Cosmonauts

**Lightweight background and stream processing for Ruby**

![logo.png](logo.png)
</div>

---

## 📖 Index

- [Why?](#-why)
- [Features](#-features)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Core Concepts](#-core-concepts)
  - [Jobs](#jobs)
  - [Streams](#streams)
  - [Configuration](#configuration)
- [Advanced Usage](#-advanced-usage)
- [CLI Reference](#-cli-reference)
- [Deployment](#-deployment)
- [Monitoring](#-monitoring)
- [Examples](#-examples)

---

## 🎯 Why?
Among many others, why creating another? Cosmonauts is a background processing framework for Ruby, powered by **[NATS](https://nats.io/)**.
It's designed to solve the fundamental scaling problems that plague Redis/DB-based job queues and at the same time to provide both job and stream
processing capabilities.

### The Problem with Redis at Scale

- **Single-threaded command processing** - All operations serialized, creating contention with many workers
- **Memory-only persistence** - Everything must fit in RAM, expensive to scale
- **Vertical scaling only** - Can't truly distribute a single queue across nodes
- **Polling overhead** - Thousands of blocked connections
- **No native backpressure** - Queues can grow unbounded
- **Weak durability** - Async replication can lose jobs during failures 

**Note:** Alternatives like Dragonfly solve the threading bottleneck but still face memory/scaling limitations.

### The Problem with Database-Backed Queues at Scale

- **Database contention** - Polling queries compete with application queries for resources
- **Connection pool pressure** - Workers consume database connections, starving the application
- **Row-level locking overhead** - `SELECT FOR UPDATE SKIP LOCKED` still scans rows under high concurrency
- **Vacuum/autovacuum impact** - High-churn job tables degrade database performance
- **Vertical scaling only** - Limited by single database instance capabilities
- **Index bloat** - High UPDATE/DELETE volume causes index degradation over time
- **Table bloat** - Constant row updates fragment tables, requiring maintenance
- **`LISTEN/NOTIFY` limitations** - 8KB payload limit, no persistence, breaks down at high volumes (10K+ notifications/sec)
- **No native horizontal scaling** - Cannot distribute a single job queue across multiple database nodes

**Note:** Solutions using DB might be ok for moderate workloads but face these fundamental limitations at higher scales.

### The Solution

Built on **NATS**, `cosmonauts` provides:

✅ **True horizontal scaling** - Distribute streams across cluster nodes  
✅ **Disk-backed persistence** - TB-scale queues with memory cache   
✅ **Replicated acknowledgments** - Survive multi-node failures  
✅ **Built-in flow control** - Automatic backpressure  
✅ **Multi-DC support** - Native geo-distribution, and super clusters  
✅ **High throughput & low latency** - Millions of messages per second  
✅ **Stream processing** - Beyond simple job queues  

---

## ✨ Features

### 🎪 Job Processing
- **Familiar compatible API** - Easy migration from existing codebases
- **Priority queues** - Multiple priority levels (critical, high, default, low)
- **Scheduled jobs** - Execute jobs at specific times or after delays
- **Automatic retries** - Configurable retry strategies with exponential backoff
- **Dead letter queue** - Capture permanently failed jobs
- **Job uniqueness** - Prevent duplicate job execution

### 🌊 Stream Processing
- **Real-time data streams** - Process continuous event streams
- **Batch processing** - Handle multiple messages efficiently
- **Message replay** - Reprocess messages from any point in time
- **Consumer groups** - Multiple consumers with load balancing
- **Exactly-once semantics** - With proper configuration
- **Custom serialization** - JSON, MessagePack, Protobuf support

---

## 📦 Installation

Add to your `Gemfile`:

```ruby
gem "cosmonauts"
```

### Prerequisites

- **Ruby 3.1.0+**
- **NATS Server**

### Install NATS Server

https://docs.nats.io/running-a-nats-service/introduction/installation

---

## 🚀 Quick Start

### 1. Create a Job

```ruby
# app/jobs/send_email_job.rb
class SendEmailJob
  include Cosmo::Job

  # configure job options (optional)
  options stream: :default, retry: 3, dead: true

  def perform(user_id, email_type)
    user = User.find(user_id)
    UserMailer.send(email_type, user).deliver_now
    logger.info "Email sent to user #{user_id}"
  end
end
```

### 2. Enqueue Jobs

```ruby
# Enqueue immediately
SendEmailJob.perform_async(123, 'welcome')

# Schedule for later
SendEmailJob.perform_in(1.hour, 123, 'reminder')
SendEmailJob.perform_at(Time.now + 24.hours, 123, 'follow_up')

# Synchronous execution (for testing)
SendEmailJob.perform_sync(123, 'test')
```

### 3. Create Configuration

```yaml
# config/cosmo.yml
timeout: 25
max_retries: &max_retries 3
concurrency: &concurrency 1

consumers:
  jobs:
    critical:
      <<: &config
        ack_policy: explicit      # each individual message must be acknowledged
        max_deliver: *max_retries # max number of times a message delivery will be attempted
        max_ack_pending: 3        # maximum number of messages w/o ack
        ack_wait: 60              # duration server waits for ack of message once it's delivered
        subject: jobs.%{name}.>
      priority: 50
    high:
      <<: *config
      priority: 30
    default:
      <<: *config
      priority: 15
    low:
      <<: *config
      priority: 5
    scheduled:
      <<: *config
      max_deliver: 1
      max_ack_pending: 100
      ack_wait: 10

streams:
  critical:
    <<: &config
      storage: file
      retention: workqueue
      duplicate_window: 120 # 2m
      discard: old
      allow_direct: true
      subjects:
        - jobs.%{name}.>
    description: Very critical priority jobs
  high:
    <<: *config
    description: Higher priority jobs
  default:
    <<: *config
    description: Default priority jobs
  low:
    <<: *config
    description: Lower priority jobs
  scheduled:
    <<: *config
    description: Scheduled jobs
  dead:
    <<: *config
    retention: limits
    max_msgs: 10000
    max_age: 604800 # 7d
    description: Broken jobs (DLQ)
```

### 4. Setup Streams

```bash
# Create streams in NATS
cosmo -C config/cosmo.yml --setup
```

### 5. Start Processing

```bash
# Start job processor
cosmo -C config/cosmo.yml -c 10 jobs

# Or with auto-require
cosmo -C config/cosmo.yml -r ./app/jobs -c 10 jobs
```

---

## 💡 Core Concepts

### Jobs

Jobs are simple background tasks. They follow a familiar pattern:

#### Basic Job

```ruby
class ReportGeneratorJob
  include Cosmo::Job

  def perform(report_id)
    report = Report.find(report_id)
    report.generate!
  end
end

# Enqueue
ReportGeneratorJob.perform_async(42)
```

#### Job Options

```ruby
class CriticalJob
  include Cosmo::Job

  options(
    stream: :critical,  # Which stream to use
    retry: 5,          # Number of retry attempts
    dead: true         # Send to dead queue after max retries
  )

  def perform(*args)
    # Your logic here
  end
end
```

#### Scheduled Jobs

```ruby
# Execute in 30 minutes
CleanupJob.perform_in(30.minutes, resource_id)

# Execute at specific time
ReminderJob.perform_at(Time.parse('2026-01-25 10:00:00'), user_id)
```

#### Job Lifecycle

```ruby
class ComplexJob
  include Cosmo::Job

  def perform(data)
    logger.info "Starting job #{jid}"  # jid = unique job ID
    
    # Your processing logic
    process_data(data)
    
    logger.info "Job completed"
  rescue StandardError => e
    logger.error "Job failed: #{e.message}"
    raise  # Will trigger retry mechanism
  end
end
```

### Streams

Streams enable continuous processing of event data, ideal for real-time analytics, ETL pipelines, and event-driven architectures.

#### Basic Stream

```ruby
class ClicksProcessor
  include Cosmo::Stream

  options(
    stream: :clickstream,
    batch_size: 100,
    consumer: {
      ack_policy: "explicit",
      max_deliver: 3,
      max_ack_pending: 100,
      subjects: ["events.clicks.>"]
    }
  )

  def process(messages)
    # Process batch of messages
    messages.each do |message|
      process_one(message)
    end
  end

  def process_one(message)
    data = message.data
    logger.info "Processing click: #{data.inspect}"
    
    # Your processing logic
    Analytics.track_click(data)
    
    # Acknowledge successful processing
    message.ack
  end
end
```

#### Publishing to Streams

```ruby
# Publish single message
ClicksProcessor.publish(
  { user_id: 123, page: '/home', timestamp: Time.now },
  subject: 'events.clicks.homepage'
)

# Using publisher directly
Cosmo::Publisher.publish(
  'events.clicks.product',
  { user_id: 456, product_id: 789 },
  stream: :clickstream
)
```

#### Stream Configuration

```ruby
class DataPipeline
  include Cosmo::Stream

  options(
    stream: :pipeline,
    consumer_name: 'pipeline-consumer',
    batch_size: 50,
    start_position: :last,  # Start from last message
    consumer: {
      ack_policy: "explicit",
      max_deliver: 5,
      max_ack_pending: 50,
      ack_wait: 30,
      subjects: ["data.raw.>"]
    },
    publisher: {
      subject: "data.processed.%{name}",
      serializer: CustomSerializer  # Optional custom serializer
    }
  )

  def process_one(message)
    # Transform data
    transformed = transform(message.data)
    
    # Publish to next stage
    publish(transformed, subject: 'data.processed.stage2')
    
    # Acknowledge original message
    message.ack
  end
end
```

#### Message Acknowledgment Strategies

```ruby
def process_one(message)
  # Success - acknowledge
  message.ack
  
  # Temporary failure - requeue (will retry)
  message.nack(delay: 5_000_000_000)  # 5-second delay (in nanoseconds)
  
  # Permanent failure - terminate (won't retry)
  message.term
end
```

#### Stream Replay

```ruby
# Start from beginning
options start_position: :first

# Start from last message
options start_position: :last

# Start from specific time
options start_position: '2026-01-20T10:00:00Z'
options start_position: 10.minutes.ago

# Start from new messages only
options start_position: :new
```

### Configuration

#### File-Based Configuration

```yaml
# config/cosmo.yml
timeout: 25          # Shutdown timeout in seconds
concurrency: 10      # Number of worker threads
max_retries: 3       # Default max retries

consumers:
  streams:
    - class: MyStream
      consumer_name: my-consumer
      batch_size: 50
      stream: my_stream
      consumer:
        ack_policy: explicit
        max_deliver: 1
        max_ack_pending: 3
        ack_wait: 30
        subjects:
          - "%{name}.>"
      publisher:
        subject: "%{name}.default"
        serializer:

streams:
  my_stream:
    storage: file        # file or memory
    retention: limits    # append only stream
    max_age: 86400       # 1d
    duplicate_window: 60 # 1m
    discard: old         # Discard old messages when full
    allow_direct: true
    subjects:
      - my_stream.>
    description: My cool stream
```

#### Programmatic Configuration

```ruby
# config/initializers/cosmo.rb
Cosmo::Config.set(:concurrency, 20)
Cosmo::Config.set(:timeout, 30)
Cosmo::Config.set(:streams, :custom, {
  storage: 'file',
  retention: 'workqueue',
  subjects: ['custom.>']
})
```

#### Environment Variables

```bash
# NATS connection
export NATS_URL=nats://localhost:4222

# Processor tuning
export COSMO_JOBS_FETCH_TIMEOUT=0.1
export COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT=5
export COSMO_STREAMS_FETCH_TIMEOUT=0.1
```

---

## 🔧 Advanced Usage

### Priority Queues

Configure different priorities with weighted polling:

```ruby
# Jobs
class UrgentJob
  include Cosmo::Job
  options stream: :critical
end

class NormalJob
  include Cosmo::Job
  options stream: :default
end

class BackgroundJob
  include Cosmo::Job
  options stream: :low
end
```

```yaml
# config/cosmo.yml
consumers:
  jobs:
    critical:
      priority: 50    # Polled 50x more frequently
      subject: jobs.critical.>
    default:
      priority: 15
      subject: jobs.default.>
    low:
      priority: 5
      subject: jobs.low.>
```

### Custom Serializers

Implement custom serialization for better performance:

```ruby
# lib/message_pack_serializer.rb
require "msgpack"

module MessagePackSerializer
  module_function

  def serialize(data)
    MessagePack.pack(data)
  end

  def deserialize(payload)
    MessagePack.unpack(payload)
  end
end

class FastStream
  include Cosmo::Stream

  options(
    publisher: {
      subject: 'fast.data',
      serializer: MessagePackSerializer
    }
  )
end
```

### Error Handling

```ruby
class ResilientJob
  include Cosmo::Job

  options retry: 5, dead: true

  def perform(data)
    process_data(data)
  rescue RetryableError => e
    logger.warn "Retryable error: #{e.message}"
    raise  # Will retry
  rescue FatalError => e
    logger.error "Fatal error: #{e.message}"
    # Don't raise - won't retry, marked as done
  end
end
```

### Testing

```ruby
# test/jobs/send_email_job_test.rb
require 'test_helper'

class SendEmailJobTest < Minitest::Test
  def test_perform
    # Synchronous execution for testing
    assert_nothing_raised do
      SendEmailJob.perform_sync(123, 'welcome')
    end
  end

  def test_enqueue
    # Test job creation
    jid = SendEmailJob.perform_async(123, 'welcome')
    assert_kind_of String, jid
  end
end
```

### Batching

Process multiple messages efficiently:

```ruby
class BatchProcessor
  include Cosmo::Stream

  options batch_size: 100

  def process(messages)
    # Bulk process for efficiency
    data = messages.map(&:data)
    Database.bulk_insert(data)
    
    # Bulk acknowledge
    messages.each(&:ack)
  end
end
```

### Dead Letter Queue

Handle permanently failed jobs:

```ruby
class FailureHandler
  include Cosmo::Stream

  options(
    consumer: {
      subjects: ['jobs.*.dead']
    }
  )

  def process_one(message)
    job_data = message.data
    
    # Alert operations
    Alerting.notify_failed_job(job_data)
    
    # Store for investigation
    FailedJob.create!(
      jid: job_data[:jid],
      class_name: job_data[:class],
      args: job_data[:args],
      error: message.header['X-Error']
    )
    
    message.ack
  end
end
```

---

## 🖥️ CLI Reference

### Basic Commands

```bash
# Display help
cosmo --help

# Show version
cosmo --version

# Setup streams
cosmo -C config/cosmo.yml --setup
```

### Running Processors

```bash
# Process jobs only
cosmo -C config/cosmo.yml jobs

# Process streams only
cosmo -C config/cosmo.yml streams

# Process both (default)
cosmo -C config/cosmo.yml

# With concurrency
cosmo -C config/cosmo.yml -c 20 jobs

# With auto-require
cosmo -C config/cosmo.yml -r ./app/jobs -c 10 jobs

# Custom shutdown timeout
cosmo -C config/cosmo.yml -t 60 jobs
```

### Flags

| Flag | Description | Example |
|------|-------------|---------|
| `-c, --concurrency INT` | Number of worker threads | `-c 20` |
| `-r, --require PATH` | Path to files/directory to require | `-r ./app/jobs` |
| `-t, --timeout NUM` | Shutdown timeout in seconds | `-t 60` |
| `-C, --config PATH` | Path to config file | `-C config/cosmo.yml` |
| `-S, --setup` | Create/update streams and exit | `--setup` |
| `-v, --version` | Print version | `--version` |

### Commands

- **`jobs`** - Run job processors only
- **`streams`** - Run stream processors only
- *(no command)* - Run all processors

---

## 🚢 Deployment

### Production Setup

#### 1. NATS Cluster

```bash
# nats-server-1.conf
port: 4222
http_port: 8222

jetstream {
  store_dir: /var/lib/nats
  max_mem: 1G
  max_file: 10G
}

cluster {
  name: cosmo-cluster
  listen: 0.0.0.0:6222
  routes: [
    nats://nats-2:6222
    nats://nats-3:6222
  ]
}
```

Start cluster:
```bash
nats-server -c nats-server-1.conf
nats-server -c nats-server-2.conf
nats-server -c nats-server-3.conf
```

#### 2. Docker Setup

```dockerfile
# Dockerfile
FROM ruby:3.2-alpine

RUN apk add --no-cache build-base

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

CMD ["bundle", "exec", "cosmo", "-C", "config/cosmo.yml", "-c", "20", "jobs"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  nats-1:
    image: nats:latest
    command: -js -c /etc/nats/nats-server.conf
    volumes:
      - ./nats-1.conf:/etc/nats/nats-server.conf
      - nats1-data:/var/lib/nats
    ports:
      - "4222:4222"
      - "8222:8222"

  nats-2:
    image: nats:latest
    command: -js -c /etc/nats/nats-server.conf
    volumes:
      - ./nats-2.conf:/etc/nats/nats-server.conf
      - nats2-data:/var/lib/nats

  nats-3:
    image: nats:latest
    command: -js -c /etc/nats/nats-server.conf
    volumes:
      - ./nats-3.conf:/etc/nats/nats-server.conf
      - nats3-data:/var/lib/nats

  worker:
    build: .
    environment:
      NATS_URL: nats://nats-1:4222,nats://nats-2:4222,nats://nats-3:4222
    depends_on:
      - nats-1
      - nats-2
      - nats-3
    deploy:
      replicas: 3

volumes:
  nats1-data:
  nats2-data:
  nats3-data:
```

#### 3. Kubernetes Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cosmo-workers
spec:
  replicas: 5
  selector:
    matchLabels:
      app: cosmo-worker
  template:
    metadata:
      labels:
        app: cosmo-worker
    spec:
      containers:
      - name: worker
        image: myapp/cosmo-worker:latest
        env:
        - name: NATS_URL
          value: "nats://nats-cluster:4222"
        - name: RAILS_ENV
          value: "production"
        resources:
          requests:
            memory: "256Mi"
            cpu: "500m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
        command:
        - bundle
        - exec
        - cosmo
        - -C
        - config/cosmo.yml
        - -c
        - "20"
        - jobs
```

### Systemd Service

```ini
# /etc/systemd/system/cosmo.service
[Unit]
Description=Cosmo Background Processor
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/myapp
Environment=RAILS_ENV=production
Environment=NATS_URL=nats://localhost:4222
ExecStart=/usr/local/bin/bundle exec cosmo -C config/cosmo.yml -c 20 jobs
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cosmo

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable cosmo
sudo systemctl start cosmo
sudo systemctl status cosmo
```

---

## 📊 Monitoring

### Logging

Cosmonauts provides structured logging with context:

```ruby
# Logs include:
# - timestamp
# - severity
# - pid (process ID)
# - tid (thread ID)
# - jid (job ID for jobs)
# - elapsed time
# - stream metadata

# Example output:
# 2026-01-23T10:15:30.123Z INFO pid=12345 tid=abc123 jid=def456: start
# 2026-01-23T10:15:32.456Z INFO pid=12345 tid=abc123 jid=def456 elapsed=2.333: done
```

### Metrics

Access NATS JetStream metrics:

```ruby
# Get stream info
client = Cosmo::Client.instance
info = client.stream_info('default')

puts info.state.messages     # Total messages
puts info.state.bytes         # Total bytes
puts info.state.first_seq     # First sequence
puts info.state.last_seq      # Last sequence
puts info.state.consumer_count # Number of consumers
```

### Prometheus Integration

NATS Server exposes Prometheus metrics on port 8222:

```yaml
# nats-server.conf
http_port: 8222

# Prometheus scrape config
scrape_configs:
  - job_name: 'nats'
    static_configs:
      - targets: ['nats-server:8222']
```

Key metrics:
- `jetstream_server_store_msgs` - Messages in stream
- `jetstream_server_store_bytes` - Bytes in stream
- `jetstream_server_api_total` - API calls
- `jetstream_consumer_delivered_msgs` - Delivered messages
- `jetstream_consumer_ack_pending` - Pending acknowledgments

---

## 💼 Examples

### Example 1: Email Queue

```ruby
# app/jobs/email_job.rb
class EmailJob
  include Cosmo::Job
  
  options stream: :default, retry: 3

  def perform(user_id, template)
    user = User.find(user_id)
    EmailService.send(user.email, template)
    logger.info "Email sent to #{user.email}"
  end
end

# Usage
EmailJob.perform_async(123, 'welcome')
EmailJob.perform_in(1.day, 123, 'followup')
```

### Example 2: Image Processing Pipeline

```ruby
# app/streams/image_processor.rb
class ImageProcessor
  include Cosmo::Stream

  options(
    stream: :images,
    batch_size: 10,
    consumer: {
      ack_policy: 'explicit',
      max_deliver: 3,
      subjects: ['images.uploaded.>']
    },
    publisher: {
      subject: 'images.processed.%{name}'
    }
  )

  def process_one(message)
    image_data = message.data
    
    # Process image
    processed = ImageService.process(
      image_data['url'],
      sizes: ['thumbnail', 'medium', 'large']
    )
    
    # Publish to next stage
    publish(processed, subject: 'images.processed.optimized')
    
    message.ack
  rescue StandardError => e
    logger.error "Image processing failed: #{e.message}"
    message.nack(delay: 30_000_000_000) # Retry in 30 seconds
  end
end

# Usage
ImageProcessor.publish(
  { url: 'https://example.com/image.jpg', user_id: 123 },
  subject: 'images.uploaded.user'
)
```

### Example 3: Real-Time Analytics

```ruby
# app/streams/analytics_aggregator.rb
class AnalyticsAggregator
  include Cosmo::Stream

  options(
    stream: :analytics,
    batch_size: 1000,
    start_position: :new,
    consumer: {
      ack_policy: 'explicit',
      max_deliver: 1,
      subjects: ['events.*.>']
    }
  )

  def process(messages)
    # Batch process for efficiency
    events = messages.map(&:data)
    
    # Aggregate by type
    aggregates = events.group_by { |e| e['event_type'] }
                       .transform_values(&:count)
    
    # Store aggregates
    Analytics.bulk_insert(aggregates)
    
    # Bulk acknowledge
    messages.each(&:ack)
    
    logger.info "Processed #{messages.count} events"
  end
end
```

### Example 4: Scheduled Reports

```ruby
# app/jobs/daily_report_job.rb
class DailyReportJob
  include Cosmo::Job

  options stream: :low, retry: 2

  def perform(report_type, recipient_email)
    report = ReportGenerator.generate(report_type, Date.today)
    ReportMailer.send_report(recipient_email, report).deliver_now
    logger.info "Daily report sent to #{recipient_email}"
  end
end

# Schedule daily at 9 AM
def schedule_daily_reports
  User.find_each do |user|
    next_run = Time.now.change(hour: 9, min: 0) + 1.day
    DailyReportJob.perform_at(next_run, 'daily', user.email)
  end
end
```

### Example 5: Webhook Processor

```ruby
# app/streams/webhook_processor.rb
class WebhookProcessor
  include Cosmo::Stream

  options(
    stream: :webhooks,
    batch_size: 50,
    consumer: {
      ack_policy: 'explicit',
      max_deliver: 5,
      subjects: ['webhooks.incoming.>']
    }
  )

  def process_one(message)
    webhook_data = message.data
    
    # Validate signature
    unless valid_signature?(webhook_data)
      logger.warn "Invalid webhook signature"
      message.term
      return
    end
    
    # Process webhook
    WebhookHandler.handle(webhook_data)
    
    message.ack
  rescue WebhookError => e
    logger.error "Webhook error: #{e.message}"
    message.nack(delay: 60_000_000_000) # Retry in 1 minute
  end
  
  private
  
  def valid_signature?(data)
    # Implement signature validation
    true
  end
end
```

---

<div align="center">

**Made with ❤️ for Ruby**

*Blast off Cosmonauts! 🚀*

</div>
