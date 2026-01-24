# 🚀 Cosmonats - lightweight background and stream processing

It is a Ruby background job and stream processing framework powered by NATS JetStream.
It provides a familiar API for job queues while adding powerful stream processing capabilities,
solving the scalability limitations of Redis and database-backed queues through true horizontal scaling and
disk-backed persistence.

![logo.svg](logo.svg)

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
Among many others, why creating another? Cosmonats is a background processing framework for Ruby, powered by **[NATS](https://nats.io/)**.
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

### The Problem with RDBMS at Scale

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

Built on **NATS**, `cosmonats` provides:

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

```ruby
# Gemfile
gem "cosmonats"
```

**Requirements:** Ruby 3.1.0+, NATS Server ([installation guide](https://docs.nats.io/running-a-nats-service/introduction/installation))

---

## 🚀 Quick Start

### 1. Create a Job

```ruby
class SendEmailJob
  include Cosmo::Job

  # configure job options (optional)
  options stream: :default, retry: 3, dead: true

  def perform(user_id, email_type)
    user = User.find(user_id)
    UserMailer.send(email_type, user).deliver_now
  end
end
```

### 2. Enqueue Jobs

```ruby
SendEmailJob.perform_async(123, 'welcome')           # Immediately
SendEmailJob.perform_in(1.hour, 123, 'reminder')     # Delayed
SendEmailJob.perform_at(1.day.from_now, 123, 'test') # Scheduled
```

### 3. Configure (config/cosmo.yml)

```yaml
concurrency: 10
max_retries: 3

consumers:
  jobs:
    default:
      ack_policy: explicit
      max_deliver: 3
      max_ack_pending: 3
      ack_wait: 60

streams:
  default:
    storage: file
    retention: workqueue
    subjects: ["jobs.default.>"]
```

### 4. Setup & Run

```bash
# Setup streams
cosmo -C config/cosmo.yml --setup

# Start processing
cosmo -C config/cosmo.yml -c 10 -r ./app/jobs jobs
```

---

## 💡 Core Concepts

### Jobs

Simple background tasks with a familiar API:

```ruby
class ReportJob
  include Cosmo::Job
  
  options(
    stream: :critical,  # Stream name
    retry: 5,           # Retry attempts
    dead: true          # Use dead letter queue
  )

  def perform(report_id)
    logger.info "Processing report #{report_id}"
    Report.find(report_id).generate!
  rescue StandardError => e
    logger.error "Failed: #{e.message}"
    raise  # Triggers retry
  end
end

# Usage
ReportJob.perform_async(42)                              # Enqueue now
ReportJob.perform_in(30.minutes, 42)                     # Delayed
ReportJob.perform_at(Time.parse('2026-01-25 10:00'), 42) # Scheduled
```

### Streams

Real-time event processing with powerful features:

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

  # Process one message
  def process_one
    data = message.data
    Analytics.track_click(data)
    message.ack  # Success
  end
  
  # OR process batch
  def process(messages)
    Analytics.track_click(messages.map(&:data))
    messages.each(&:ack)
  end
end

# Publishing
ClicksProcessor.publish(
  { user_id: 123, page: '/home' },
  subject: 'events.clicks.homepage'
)

# Message acknowledgment strategies
message.ack                          # Success
message.nack(delay: 5_000_000_000)   # Retry (5 seconds in nanoseconds)
message.term                         # Permanent failure, no retry
```

### Configuration

**File-based (config/cosmo.yml):**
```yaml
timeout: 25     # Shutdown timeout in seconds
concurrency: 10 # Number of worker threads
max_retries: 3  # Default max retries

consumers:
  streams:
    - class: MyStream
      batch_size: 50
      consumer:
        ack_policy: explicit
        max_deliver: 3
        subjects: ["events.>"]

streams:
  my_stream:
    storage: file         # or memory
    retention: workqueue  # or limits
    max_age: 86400       # 1d in seconds
    subjects: ["events.>"]
```

**Programmatic:**
```ruby
Cosmo::Config.set(:concurrency, 20)
Cosmo::Config.set(:streams, :custom, { storage: 'file', subjects: ['custom.>'] })
```

**Environment variables:**
```bash
export NATS_URL=nats://localhost:4222
export COSMO_JOBS_FETCH_TIMEOUT=0.1
export COSMO_STREAMS_FETCH_TIMEOUT=0.1
```

---

## 🔧 Advanced Usage

**Priority Queues:**
```ruby
class UrgentJob
  include Cosmo::Job
  options stream: :critical  # priority: 50 in config
end

# config/cosmo.yml
consumers:
  jobs:
    critical:
      priority: 50  # Polled more frequently
    default:
      priority: 15
```

**Custom Serializers:**
```ruby
module MessagePackSerializer
  def self.serialize(data)
    MessagePack.pack(data)
  end
  
  def self.deserialize(payload)
    MessagePack.unpack(payload)
  end
end

class FastStream
  include Cosmo::Stream
  options publisher: { serializer: MessagePackSerializer }
end
```

**Error Handling:**
```ruby
class ResilientJob
  include Cosmo::Job
  options retry: 5, dead: true

  def perform(data)
    process_data(data)
  rescue RetryableError => e
    logger.warn "Retryable: #{e.message}"
    raise  # Will retry
  rescue FatalError => e
    logger.error "Fatal: #{e.message}"
    # Don't raise - won't retry
  end
end
```

**Testing:**
```ruby
# Synchronous execution
SendEmailJob.perform_sync(123, 'test')

# Test job creation
jid = SendEmailJob.perform_async(123, 'welcome')
assert_kind_of String, jid
```

---

## 🖥️ CLI Reference

```bash
# Setup streams
cosmo -C config/cosmo.yml --setup

# Run processors
cosmo -C config/cosmo.yml -c 20 -r ./app/jobs jobs     # Jobs only
cosmo -C config/cosmo.yml -c 20 streams                # Streams only
cosmo -C config/cosmo.yml -c 20                        # Both
```

**Common Flags:**

| Flag | Description | Example |
|------|-------------|---------|
| `-C, --config PATH` | Config file path | `-C config/cosmo.yml` |
| `-c, --concurrency INT` | Worker threads | `-c 20` |
| `-r, --require PATH` | Auto-require directory | `-r ./app/jobs` |
| `-t, --timeout NUM` | Shutdown timeout (sec) | `-t 60` |
| `-S, --setup` | Setup streams & exit | `--setup` |

---

## 🚢 Deployment

**NATS Cluster:**
```bash
# nats-server.conf
port: 4222
jetstream {
  store_dir: /var/lib/nats
  max_file: 10G
}
cluster {
  name: cosmo-cluster
  listen: 0.0.0.0:6222
  routes: [nats://nats-2:6222, nats://nats-3:6222]
}
```

**Docker Compose:**
```yaml
services:
  nats:
    image: nats:latest
    command: -js -c /etc/nats/nats-server.conf
    volumes:
      - ./nats.conf:/etc/nats/nats-server.conf
      - nats-data:/var/lib/nats
  
  worker:
    build: .
    environment:
      NATS_URL: nats://nats:4222
    command: bundle exec cosmo -C config/cosmo.yml -c 20 jobs
    deploy:
      replicas: 3
```

**Systemd Service:**
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

**Structured Logging:**
```
2026-01-23T10:15:30.123Z INFO pid=12345 tid=abc jid=def: start
2026-01-23T10:15:32.456Z INFO pid=12345 tid=abc jid=def elapsed=2.333: done
```

**Stream Metrics:**
```ruby
client = Cosmo::Client.instance
info = client.stream_info('default')

info.state.messages       # Total messages
info.state.bytes          # Total bytes
info.state.consumer_count # Number of consumers
```

**Prometheus:** NATS exposes metrics at `:8222/metrics`
- `jetstream_server_store_msgs` - Messages in stream
- `jetstream_consumer_delivered_msgs` - Delivered messages
- `jetstream_consumer_ack_pending` - Pending acknowledgments

---

## 💼 Examples

**Email Queue:**
```ruby
class EmailJob
  include Cosmo::Job
  options stream: :default, retry: 3

  def perform(user_id, template)
    user = User.find(user_id)
    EmailService.send(user.email, template)
  end
end

EmailJob.perform_async(123, 'welcome')
EmailJob.perform_in(1.day, 123, 'followup')
```

**Image Processing Pipeline:**
```ruby
class ImageProcessor
  include Cosmo::Stream
  options(
    stream: :images,
    consumer: { subjects: ['images.uploaded.>'] }
  )

  def process_one
    processed = ImageService.process(message.data['url'])
    publish(processed, subject: 'images.processed.optimized')
    message.ack
  rescue => e
    logger.error "Processing failed: #{e.message}"
    message.nack(delay: 30_000_000_000)
  end
end

ImageProcessor.publish({ url: 'https://example.com/image.jpg' }, subject: 'images.uploaded.user')
```

**Real-Time Analytics:**
```ruby
class AnalyticsAggregator
  include Cosmo::Stream
  options batch_size: 1000, consumer: { subjects: ['events.*.>'] }

  def process(messages)
    events = messages.map(&:data)
    aggregates = events.group_by { |e| e['type'] }.transform_values(&:count)
    Analytics.bulk_insert(aggregates)
    messages.each(&:ack)
  end
end
```

---

<div align="center">

**Made with ❤️ for Ruby**

*Blast off Cosmonats! 🚀*

</div>
