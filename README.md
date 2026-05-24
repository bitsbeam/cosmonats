# 🚀 Cosmonats

Background jobs + event streaming for Ruby — unified, in one gem, backed by NATS.
No Redis. No DB polling. Disk-backed, horizontally scalable — no message is ever silently dropped.

<div align="center">

![logo.svg](logo.svg)

[![Gem Version](https://badge.fury.io/rb/cosmonats.svg)](https://rubygems.org/gems/cosmonats)
[![Downloads](https://img.shields.io/gem/dt/cosmonats.svg)](https://rubygems.org/gems/cosmonats)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-red)](https://www.ruby-lang.org)
[![License: LGPL v3](https://img.shields.io/badge/License-LGPL%20v3-blue.svg)](LICENSE.txt)
[![Build Status](https://github.com/bitsbeam/cosmonats/actions/workflows/ci.yml/badge.svg)](https://github.com/bitsbeam/cosmonats/actions)

</div>


## ⚡ Taste it

```ruby
# Process a continuous event stream
class ClicksProcessor
  include Cosmo::Stream
  options stream: :clickstream, batch_size: 100,
          consumer: { subjects: ["events.clicks.>"] }

  def process_one
    Analytics.track(message.data)
    message.ack
  end
end

ClicksProcessor.publish({ user_id: 123, page: "/home" }, subject: "events.clicks.homepage")
```

```ruby
# Define a job
class SendEmailJob
  include Cosmo::Job
  options stream: :default, retry: 3, dead: true

  def perform(user_id, template)
    EmailService.send(user_id, template)
  end
end

# Enqueue it
SendEmailJob.perform_async(123, "welcome")
SendEmailJob.perform_in(1.day, 123, "followup")
```

```bash
bundle exec cosmo -C config/cosmo.yml -c 20 streams # Run streams
bundle exec cosmo -C config/cosmo.yml -c 20 jobs    # Run jobs
bundle exec cosmo -C config/cosmo.yml -c 20         # Run both
```


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


## 🎯 Why?

Most background job libraries use Redis or Postgres — tools that were never designed for this.

NATS is a messaging system in a single ~20MB binary with a ~10MB memory footprint — yet it delivers disk-backed persistent streams, Pub/Sub, KV store, and true
horizontal clustering at millions of messages per second.

### Killer Features:

#### — Jobs + Streams, unified in one gem.

Most Ruby gems handle exactly that — background jobs. If you also need to consume a continuous event feed, that's a second system, second config, second set of
worker processes, second Dockerfile entry. Cosmonats is the only Ruby gem with a first-class `Job` primitive *and* a first-class `Stream` primitive, sharing
one server, one config, one CLI, one monitoring endpoint.

#### — Message replay and time-travel debugging.

NATS persists messages to disk and lets any consumer rewind to any point — beginning of time, a specific timestamp, or only new messages.
- **Incident recovery** — your pipeline crashed for 3 hours. Replay from the crash timestamp.
- **New consumer bootstrap** — a new service needs historical events. Start it from the beginning.
- **Bug reproduction** — replay the exact sequence of messages that caused a production issue.

#### — Multi-datacenter queues, natively.

NATS has a first-class cluster + leaf-node architecture for geo-distribution. Spanning multiple regions or datacenters is a config block — not a separate
product or a third-party replication tool. NATS was built for edge computing, IoT, and satellite communication — multi-DC is a first-class concern, not an
afterthought.

#### — Transport-level deduplication + built-in KV. No extra infrastructure.

NATS deduplicates messages at the **broker** — same-ID messages within the configured window are dropped before they ever reach a worker. No uniqueness gems,
no advisory locks, no extra round-trips. It also ships a built-in Key/Value store usable for distributed locks and rate limiting — no Redis, no Memcached,
nothing else to run.

|                   | Redis/DB-backed               | NATS                       |
|-------------------|-------------------------------|----------------------------|
| Persistence       | In-memory / DB bloat          | Disk-backed, TB-scale      |
| Scaling           | Sentinel only / Vertical only | True horizontal clustering |
| Background jobs   | Yes                           | Yes                        |
| Stream processing | No                            | Yes                        |
| Message replay    | No                            | Yes                        |
| Backpressure      | No, grow unbounded            | Yes                        |
| Multi-DC          | Complex setup                 | Native geo-distribution    |

One NATS server replaces your message broker, job queue, and KV store — with lower operational overhead.


## ✨ Features

### 🎪 Job Processing
- **Familiar API** — `perform_async`, `perform_in`, `perform_at`
- **Priority queues** — critical, high, default, low with weighted round-robin
- **Scheduled jobs** — execute at a specific time or after a delay
- **Automatic retries** — exponential backoff, configurable attempts
- **Dead letter queue** — capture permanently failed jobs
- **Job uniqueness** — prevent duplicate execution

### 🌊 Stream Processing
- **Real-time event streams** — process continuous data feeds
- **Batch processing** — handle multiple messages in one go
- **Message replay** — reprocess from any point in time
- **Consumer groups** — load-balanced across workers
- **Custom serialization** — JSON, MessagePack, Protobuf


## 📦 Installation

```ruby
# Gemfile
gem "cosmonats"
```

**Requirements:** Ruby ≥ 3.1, NATS Server ([install guide](https://docs.nats.io/running-a-nats-service/introduction/installation))

Spin up NATS instantly with Docker:
```bash
docker run -p 4222:4222 -p 8222:8222 nats:alpine -js
```

Mount the monitoring UI in your Rack app:
```ruby
require "cosmo/web"

# Rails
mount Cosmo::Web => "/cosmo"

# Any Rack app (config.ru)
map "/cosmo" { run Cosmo::Web }
```


## 🚀 Quick Start

### 1. Create `config/cosmo.yml`

```yaml
concurrency: 5                     # Number of worker threads

consumers:                         # Declare consumer groups for streams, things that pull messages and process them
  jobs:                            # Consumer configs for jobs (or streams)
    default:                       # Stream name
      ack_policy: explicit         # Acknowledgment required for each message, can be explicit, none, or all
      max_deliver: 10              # Max retry attempts before sending to a dead stream
      max_ack_pending: 10          # Max messages waiting for ack, if exceeded, the server will stop delivering new messages until some are acked
      ack_wait: 15                 # Seconds to wait for ack before redelivering
      subject: jobs.%{name}.>      # Subject pattern for this consumer, %{name} replaced with stream name, becomes `jobs.default.>`

setup:                             # Initial stream creation only `cosmo -S`
  jobs:                            # Stream configs for jobs (or streams)
    default:                       # Stream name
      storage: file                # Storage type (file or memory)
      retention: workqueue         # Retention policy (limits, interest, workqueue). workqueue - deletes acked/nacked, limits - append only
      subjects: ["jobs.%{name}.>"] # Subject pattern for this stream, %{name} replaced with stream name
      allow_direct: true           # Allow direct messages to stream (required for web UI)
```

### 2. Create streams in NATS (one-time), grabs config from setup section of `config/cosmo.yml`

```bash
bundle exec cosmo -S
```

### 3. Define a job in `app/jobs/`

```ruby
class SendEmailJob
  include Cosmo::Job
  options stream: :default, retry: 3, dead: true

  def perform(user_id, email_type)
    UserMailer.send(email_type, user_id).deliver_now
  end
end
```

### 4. Enqueue & run

```ruby
SendEmailJob.perform_async(42, "welcome")
```

```bash
bundle exec cosmo -C config/cosmo.yml -c 10 -r ./app/jobs jobs
```


## 💡 Core Concepts

### Jobs

```ruby
class ReportJob
  include Cosmo::Job

  options(
    stream: :critical,  # Stream name
    retry: 5,           # Retry attempts
    dead: true          # Send to dead letter queue on final failure
  )

  def perform(report_id)
    logger.info "Processing report #{report_id}"
    Report.find(report_id).generate!
  rescue StandardError => e
    logger.error "Failed: #{e.message}"
    raise  # Triggers retry with exponential backoff
  end
end

ReportJob.perform_async(42)                              # Enqueue now
ReportJob.perform_in(30.minutes, 42)                     # Delayed
ReportJob.perform_at(Time.parse("2026-01-25 10:00"), 42) # Scheduled
ReportJob.perform_sync(42)                               # Inline, no NATS (great for tests)
```

### Streams

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

### Configuration

**Full `config/cosmo.yml` example:**
```yaml
timeout: 25                 # Shutdown timeout in seconds
concurrency: &concurrency 1 # Number of worker threads
max_retries: &max_retries 3 # Default max retries

stream_config: &stream_config
  storage: file         # storage type (file or memory)
  retention: workqueue  # retention policy (limits, interest, workqueue)
  duplicate_window: 120 # time window for duplicate message detection in seconds
  discard: old          # discard new messages when stream is full (discard new or old)
  allow_direct: true    # allow direct messages to stream, required for web UI
  subjects:
    - jobs.%{name}.>    # subject pattern for stream, %{name} will be replaced with stream name

consumer_config: &consumer_config
  ack_policy: explicit    # ack policy (explicit, none, all), each individual message must be acknowledged
  max_deliver: 10         # maximum number of times a message will be delivered before it's considered failed
  max_ack_pending: 20     # maximum number of messages with pending ack for this consumer
  ack_wait: 60            # time in seconds to wait for an ack before redelivering the message
  subject: jobs.%{name}.> # subject pattern for consumer, %{name} will be replaced with stream name

consumers:
  jobs:
    critical:
      <<: *consumer_config
      priority: 50
    high:
      <<: *consumer_config
      priority: 30
    default:
      <<: *consumer_config
      priority: 15
    low:
      <<: *consumer_config
      priority: 5
    scheduled:
      <<: *consumer_config
      max_deliver: 1
      max_ack_pending: 100
      ack_wait: 10

setup:
  jobs:
    critical:
      <<: *stream_config
      description: Very critical priority jobs
    high:
      <<: *stream_config
      description: Higher priority jobs
    default:
      <<: *stream_config
      description: Default priority jobs
    low:
      <<: *stream_config
      description: Lower priority jobs
    scheduled:
      <<: *stream_config
      description: Scheduled jobs
    dead:
      <<: *stream_config
      retention: limits
      max_msgs: 10000
      max_age: 604800 # 7d
      description: Broken jobs (DLQ)

development:
  verbose: false
  concurrency: *concurrency

staging:
  verbose: true
  concurrency: 3

production:
  concurrency: 3
```

**Programmatic:**
```ruby
Cosmo::Config.set(:concurrency, 20)
Cosmo::Config.set(:setup, :streams, :custom, { storage: "file", subjects: ["custom.>"] })
```

**Environment variables:**
```bash
export NATS_URL=nats://localhost:4222
export COSMO_JOBS_FETCH_TIMEOUT=0.1
export COSMO_STREAMS_FETCH_TIMEOUT=0.1
```


## 🔧 Advanced Usage

**Priority Queues:**
```ruby
class UrgentJob
  include Cosmo::Job
  options stream: :critical  # priority: 50 in config — polled most frequently
end
```

**Custom Serializers:**
```ruby
module MessagePackSerializer
  def self.serialize(data) = MessagePack.pack(data)
  def self.deserialize(payload) = MessagePack.unpack(payload)
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
    raise  # Will retry with exponential backoff
  rescue FatalError => e
    logger.error "Fatal: #{e.message}"
    # Don't raise — won't retry, won't go to DLQ
  end
end
```

**Testing:**
```ruby
# Synchronous — no NATS needed
SendEmailJob.perform_sync(123, "test")

# Async — returns a job ID
jid = SendEmailJob.perform_async(123, "welcome")
assert_kind_of String, jid
```


## 🖥️ CLI Reference

```bash
cosmo -C config/cosmo.yml --setup                  # Create streams in NATS (idempotent)
cosmo -C config/cosmo.yml -c 20 -r ./app/jobs jobs # Jobs only
cosmo -C config/cosmo.yml -c 20 streams            # Streams only
cosmo -C config/cosmo.yml -c 20                    # Both
```

| Flag                    | Description            | Example               |
|-------------------------|------------------------|-----------------------|
| `-C, --config PATH`     | Config file path       | `-C config/cosmo.yml` |
| `-c, --concurrency INT` | Worker threads         | `-c 20`               |
| `-r, --require PATH`    | Auto-require directory | `-r ./app/jobs`       |
| `-t, --timeout NUM`     | Shutdown timeout (sec) | `-t 60`               |
| `-S, --setup`           | Setup streams & exit   | `--setup`             |


## 🚢 Deployment

**NATS Cluster config:**
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

```bash
sudo systemctl enable cosmo && sudo systemctl start cosmo
```


## 📊 Monitoring

**Structured logs:**
```
2026-01-23T10:15:30.123Z INFO pid=12345 tid=abc jid=def: start
2026-01-23T10:15:32.456Z INFO pid=12345 tid=abc jid=def elapsed=2.333: done
```

**Stream Metrics:**
```ruby
client = Cosmo::Client.instance
info = client.stream_info("default")

info.state.messages       # Total messages
info.state.bytes          # Total bytes
info.state.consumer_count # Number of consumers
```

**Prometheus** — NATS exposes metrics at `:8222/metrics`:
- `jetstream_server_store_msgs` — Messages in stream
- `jetstream_consumer_delivered_msgs` — Delivered messages
- `jetstream_consumer_ack_pending` — Pending acknowledgments


## 💼 Examples

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

---

<div align="center">

**Made with ❤️ for Ruby**

*Blast off Cosmonats! 🚀*

</div>
