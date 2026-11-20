# <img src="lib/cosmo/web/assets/logo.svg" alt="" width="32" height="32" align="absmiddle"> cosmonats

Background jobs + real-time event streaming for Ruby — unified, in one gem, backed by NATS.  
**No Redis. No DB polling. Disk-backed, horizontally scalable — no message is ever silently dropped.**

<div align="center">

![logo.svg](logo.svg)

*Battle-tested in production. Tens of millions of jobs processed and counting.*

</div>


## ⚡ Taste it

```ruby
# Define a job with a familiar look
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

```ruby
# Process a continuous real-time event stream
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

```bash
bundle exec cosmo -C config/cosmo.yml -c 20         # Run jobs + streams with 20 threads
bundle exec cosmo -C config/cosmo.yml -c 20 jobs    # Jobs only
bundle exec cosmo -C config/cosmo.yml -c 20 streams # Streams only
```

## 📖 [Documentation](https://cosmonats.bitsbeam.com/docs/introduction)

- **Getting started** — [Introduction](https://cosmonats.bitsbeam.com/docs/introduction) ·
  [Installation](https://cosmonats.bitsbeam.com/docs/installation) ·
  [Quick start](https://cosmonats.bitsbeam.com/docs/quick-start)
- **Core concepts** — [Jobs](https://cosmonats.bitsbeam.com/docs/jobs) ·
  [Streams](https://cosmonats.bitsbeam.com/docs/streams) ·
  [Configuration](https://cosmonats.bitsbeam.com/docs/configuration)
- **Advanced usage** — [Cron](https://cosmonats.bitsbeam.com/docs/cron) ·
  [Priority queues and lanes](https://cosmonats.bitsbeam.com/docs/priority-queues-and-lanes) ·
  [Batches](https://cosmonats.bitsbeam.com/docs/batches) ·
  [Concurrency limiting](https://cosmonats.bitsbeam.com/docs/concurrency-limiting) ·
  [Custom serializers](https://cosmonats.bitsbeam.com/docs/serializers) ·
  [Error handling](https://cosmonats.bitsbeam.com/docs/error-handling) ·
  [Middleware](https://cosmonats.bitsbeam.com/docs/middleware) ·
  [Testing](https://cosmonats.bitsbeam.com/docs/testing)
- **Integrations** — [Active Job](https://cosmonats.bitsbeam.com/docs/active-job) ·
  [Sentry](https://cosmonats.bitsbeam.com/docs/sentry)
- **Operations** — [CLI](https://cosmonats.bitsbeam.com/docs/cli) ·
  [Deployment](https://cosmonats.bitsbeam.com/docs/deployment) ·
  [Monitoring](https://cosmonats.bitsbeam.com/docs/monitoring) ·
  [Examples](https://cosmonats.bitsbeam.com/docs/examples) ·
  [Upgrading](https://cosmonats.bitsbeam.com/docs/upgrading)

The same pages live in [`docs/`](docs) for reading on GitHub.


## 📦 Installation

```ruby
# Gemfile
gem "cosmonats"
```

**Requirements:** Ruby ≥ 3.2, NATS Server ≥ 2.14 with JetStream enabled ([install guide](https://docs.nats.io/running-a-nats-service/introduction/installation))

Spin up NATS instantly with Docker — one command, that's it:
```bash
docker run -p 4222:4222 -p 8222:8222 nats:alpine -js
```

Then follow the [quick start](https://cosmonats.bitsbeam.com/docs/quick-start).


## 🎯 Why?

Most background job libraries use Redis or Postgres — tools that were never designed for this. NATS is messaging
first, then KV: a ~20 MB binary with disk-backed persistent streams, true horizontal clustering, and clients in every
major language. One NATS server replaces your message broker, job queue, and KV store.

|                   | Redis/DB-backed               | NATS/Cosmonats             |
|-------------------|-------------------------------|----------------------------|
| Persistence       | In-memory / DB bloat          | Disk-backed, TB-scale      |
| Scaling           | Sentinel only / Vertical only | True horizontal clustering |
| Background jobs   | Yes                           | Yes                        |
| Real-time stream  | No                            | Yes                        |
| Zero message loss | No                            | Yes                        |
| Message replay    | No                            | Yes                        |
| Backpressure      | No, grow unbounded            | Yes                        |
| Multi-DC          | Complex setup                 | Native geo-distribution    |

Read more in the [introduction](https://cosmonats.bitsbeam.com/docs/introduction).

---

<div align="center">

**Made with ❤️ for Ruby**

*Blast off Cosmonats! 🚀*

</div>
