# AGENTS.md — Cosmonats Codebase Guide

## Overview
**cosmonats** is a Ruby gem (module namespace `Cosmo`) providing background job and stream processing backed by **NATS JetStream**. Requires Ruby ≥ 3.1. No Rails dependency — works with any framework.

---

## Architecture

```
CLI → Engine → ThreadPool
                  ├── Job::Processor   (pull-subscribes per-stream, weighted round-robin)
                  └── Stream::Processor (pull-subscribes per class/config entry)
                        ↑
                  Client (nc + js)   ← Publisher (singleton)
                        ↑
                  NATS JetStream
```

- **`Cosmo::Client`** (`lib/cosmo/client.rb`) — singleton NATS connection. `client.nc` = raw NATS, `client.js` = JetStream. URL from `NATS_URL` env (default `nats://localhost:4222`).
- **`Cosmo::Config`** (`lib/cosmo/config.rb`) — YAML config layered over `lib/cosmo/defaults.yml`. Default file: `config/cosmo.yml`. Call `Config.set(key, value)` for programmatic overrides.
- **`Cosmo::Engine`** (`lib/cosmo/engine.rb`) — singleton; starts `Job::Processor` and/or `Stream::Processor` sharing one `Utils::ThreadPool`. Handles `INT`/`TERM` signals for graceful shutdown.
- **`Cosmo::Publisher`** (`lib/cosmo/publisher.rb`) — singleton; serializes and publishes to NATS. Job publishing goes via `publish_job(data)`, stream publishing via `publish(subject, data, ...)`.
- **`Cosmo::Web`** (`lib/cosmo/web.rb`) — Rack app for monitoring UI using HTMX; served via `config.ru`.

---

## Adding Jobs vs Streams

**Jobs** — one-shot tasks, Sidekiq-like API:
```ruby
class MyJob
  include Cosmo::Job
  options stream: :default, retry: 3, dead: true
  def perform(arg); end
end
MyJob.perform_async(arg)          # async
MyJob.perform_in(5.minutes, arg)  # delayed (uses :scheduled stream)
MyJob.perform_sync(arg)           # inline, no NATS
```

**Streams** — continuous event processors:
```ruby
class MyProcessor
  include Cosmo::Stream
  options stream: :my_stream, batch_size: 50,
          consumer: { subjects: ["events.my_processor.>"] }
  def process_one          # single message; use `message` accessor
    message.ack
  end
  # OR override process(messages) for batch
end
MyProcessor.publish({ key: "val" }, subject: "events.my_processor.thing")
```
`Stream` classes **auto-register** when `options` is called (`Config.system[:streams]`). Streams in `app/streams/` are eagerly loaded by the CLI.

---

## Subject & Stream Naming Conventions

- **Job subjects**: `jobs.<stream_name>.<underscored_class_name>` — e.g. `jobs.default.send_email_job`
- **Dead letter**: `jobs.dead.<underscored_class_name>`
- **Scheduled jobs**: routed through the `:scheduled` stream with headers `X-Execute-At`, `X-Stream`, `X-Subject`
- **Stream subjects**: default `<underscored_class_name>.>` — interpolated via Ruby `format(str, name:)`
- Config YAML `subject`/`subjects` fields use `%{name}` format strings interpolated with the stream name (see `Config.normalize!`)

---

## Configuration Gotchas

- `max_age` and `duplicate_window` in **YAML are in seconds** — `Config.normalize!` converts to nanoseconds automatically.
- `message.nack(delay:)` takes **nanoseconds** directly (e.g. `30_000_000_000` = 30s).
- Retry backoff formula: `((attempt**4) + 15) * 1_000_000_000` ns (see `Job::Processor#handle_failure`).
- `fetch_timeout: 0` or negative is rejected — minimum enforced from `Stream::Data::DEFAULTS[:fetch_timeout]`.
- Priority queues: `priority:` in consumer config fills a weighted array — higher number = polled more frequently.

---

## Developer Workflows

```bash
# Install deps
bundle install

# Run all tests (requires live NATS — see docker-compose.yml)
bundle exec rake spec
# or
bundle exec rspec

# Lint
bundle exec rubocop

# Setup NATS streams (idempotent)
cosmo -C config/cosmo.yml --setup

# Run workers
cosmo -C config/cosmo.yml -c 10 -r ./app/jobs jobs
cosmo -C config/cosmo.yml -c 10 streams
cosmo -C config/cosmo.yml -c 10            # both

# Start monitoring UI
bundle exec rackup
```

Spin up NATS for local dev/test:
```bash
docker compose up nats
```

---

## Testing Patterns

- Specs assume a **live NATS connection**; use `clean_streams` (from `spec/support/global_helpers.rb`) to purge streams between tests.
- `RSpec.shared_context "Global helpers"` is included globally; gives `client` and `clean_streams` helpers.
- Use `perform_sync` to test job logic without NATS.

---

## Singleton Pattern
`Client`, `Config`, `Engine`, `Publisher`, `API::Counter`, `API::Busy` all use `@instance ||= new`. Reset between tests if needed by clearing `@instance` via `instance_variable_set`.

---

## Key Files
| Purpose | Path |
|---|---|
| Default config values | `lib/cosmo/defaults.yml` |
| Job mixin + ClassMethods | `lib/cosmo/job.rb` + `lib/cosmo/job/` |
| Stream mixin + registration | `lib/cosmo/stream.rb` + `lib/cosmo/stream/` |
| Engine / signal handling | `lib/cosmo/engine.rb` |
| NATS client wrapper | `lib/cosmo/client.rb` |
| Structured logger | `lib/cosmo/logger.rb` |
| CLI entrypoint | `lib/cosmo/cli.rb` |
| Monitoring Rack app | `lib/cosmo/web.rb` |
| RBS type signatures | `sig/` |

