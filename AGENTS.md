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
- **`Cosmo::Config`** (`lib/cosmo/config.rb`) — a `Hash` subclass holding the parsed YAML. No defaults ship with the gem: `Config.load(path)` **replaces** the contents with that file (default `config/cosmo.yml`), so the config file must be explicit and complete. Class-level `[]`, `fetch`, `dig`, `to_h`, `set`, `load` are delegated to the singleton; call `Config.set(:key, value)` for programmatic overrides.
- **`Cosmo::Engine`** (`lib/cosmo/engine.rb`) — singleton; starts `Job::Processor` and/or `Stream::Processor` sharing one `Utils::ThreadPool`. Traps `INT`/`TERM` (graceful shutdown), `TSTP`/`CONT` (quiet / resume fetching), and `USR1` (quiet, then exit once in-flight work drains).
- **`Cosmo::Publisher`** (`lib/cosmo/publisher.rb`) — singleton; serializes and publishes to NATS. Job publishing goes via `publish_job(data)`, stream publishing via `publish(subject, data, ...)`.
- **`Cosmo::Web`** (`lib/cosmo/web.rb`) — Rack app for the monitoring UI (HTMX), served via `config.ru`. Routes are matched against absolute paths, so it does not yet mount under a path prefix. **It has no authentication and no CSRF protection**, while exposing destructive routes (retry/delete dead jobs, pause streams, delete/run crons) — never expose it publicly.
- **`Cosmo::Batch`** (`lib/cosmo/batch.rb`) — groups jobs and fires a `:success`/`:complete` callback when the group finishes; state lives in `API::Counter` counters plus a TTL'd KV bucket. Nested batches are created with `Batch.new(parent: bid)`.
- **`Cosmo::API::Cron`** (`lib/cosmo/api/cron.rb`) — recurring jobs use **NATS 2.14 server-side message schedules** (`Nats-Schedule` headers on a message stored at `cosmo.cron.<stream>.>`), not a scheduler thread. Nothing to elect a leader for; whatever is deployed in NATS is exactly what the UI shows.
- **`Cosmo::Job::Limit`** (`lib/cosmo/job/limit.rb`) — distributed concurrency limiter; numbered KV slots acquired via CAS, auto-expired by `Nats-TTL`.
- **`Cosmo::ActiveJobAdapter`** (`lib/cosmo/active_job/`) — `config.active_job.queue_adapter = :cosmonats`; the ActiveJob queue name maps to a Cosmo stream. Wired up automatically inside Rails by `Cosmo::Railtie`. See `docs/active_job.md`.
- **Sentry** (`lib/cosmo/sentry/`) — `require "cosmo/sentry/auto"` prepends a module onto `Job::Processor`. There is no formal middleware chain yet; `Job::Processor#perform_job(job_instance, data:, message:, duration:)` is the seam to `prepend` around.

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
`Stream` classes **auto-register** when `options` is called (`Config.internal[:streams]`). Streams in `app/streams/` are eagerly loaded by the CLI.

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
- `message.nak(delay:)` takes **nanoseconds** directly (e.g. `30_000_000_000` = 30s). `nack` is an alias of `nak`; the underlying nats-pure method is `nak`.
- Retry backoff: `attempt**4 + 15` **seconds**, converted with `Config.to_ns` at NAK time (`Job::Processor#retry_delay`). Override per job class with the `retry_in: ->(count, exception) { seconds }` option; a non-numeric/non-positive return or a raise falls back to the default.
- A job's `retry:` is capped by its consumer's `max_deliver`: exceeding it dead-letters one delivery early with a warning rather than stranding the message (`Job::Processor#deliver_cap`).
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

- Specs assume a **live NATS connection**; use `destroy_streams` (from `spec/support/global_helpers.rb`) to purge streams between tests.
- `RSpec.shared_context "Global helpers"` is included globally; gives `client` and `destroy_streams` helpers.
- Use `perform_sync` to test job logic without NATS.

---

## Singleton Pattern
`Client`, `Config`, `Engine`, `Publisher`, `API::Counter`, `API::Busy` all use `@instance ||= new`. Reset between tests if needed by clearing `@instance` via `instance_variable_set`.

---

## Key Files
| Purpose | Path |
|---|---|
| Config file (not in repo — see README §"Create `config/cosmo.yml`"; test copy at `spec/support/cosmo.yml`) | `config/cosmo.yml` |
| Job mixin + ClassMethods | `lib/cosmo/job.rb` + `lib/cosmo/job/` |
| Batch grouping + callbacks | `lib/cosmo/batch.rb` + `lib/cosmo/api/batch.rb` |
| Cron schedules (NATS 2.14) | `lib/cosmo/api/cron.rb` + `lib/cosmo/api/cron/entry.rb` |
| Concurrency limiter | `lib/cosmo/job/limit.rb` |
| ActiveJob adapter + Railtie | `lib/cosmo/active_job/` + `lib/cosmo/railtie.rb` |
| Vendored nats-pure fixes | `lib/cosmo/utils/overrides.rb` |
| Stream mixin + registration | `lib/cosmo/stream.rb` + `lib/cosmo/stream/` |
| Engine / signal handling | `lib/cosmo/engine.rb` |
| NATS client wrapper | `lib/cosmo/client.rb` |
| Structured logger | `lib/cosmo/logger.rb` |
| CLI entrypoint | `lib/cosmo/cli.rb` |
| Monitoring Rack app | `lib/cosmo/web.rb` |
| RBS type signatures | `sig/` |

