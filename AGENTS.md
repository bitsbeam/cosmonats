# AGENTS.md — Cosmonats Codebase Guide

## Overview
**cosmonats** is a Ruby gem (module namespace `Cosmo`) providing background job and stream processing backed by
**NATS JetStream**. Requires Ruby ≥ 3.1. No Rails dependency — works with any framework.

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

- **`Cosmo::Client`** (`lib/cosmo/client.rb`) — singleton NATS connection. `client.nc` = raw NATS, `client.js` =
  JetStream. URL from `NATS_URL` env (default `nats://localhost:4222`).
- **`Cosmo::Config`** (`lib/cosmo/config.rb`) — a `Hash` subclass holding the effective YAML config.
  `Config.load(path, overrides:)` replaces the contents with `Config.build`: the shipped `lib/cosmo/config/cosmo.yml`
  with the user's file deep-merged over it (no file → the defaults alone), then `overrides` — the CLI's `-c`/`-t`/`-p`,
  so flags always win. The one exception: a user `setup.jobs` replaces the built-in `default` job stream and consumer
  instead of merging. YAML holds user-defined things only — `scheduled`/`dead` under `setup.jobs`/`consumers.jobs`, or
  `batch_expiry`, raise `ConfigError`. `load` is the only writer of YAML keys (there is no `Config.set`). Class-level
  `[]`, `fetch`, `dig`, `load`, `server_middleware`, `replicas`, `scheduled`, `dead`, `batches` are delegated to the
  singleton. `Cosmo.configure { |config| }` yields the same singleton. `server_middleware` and the service settings are instance variables, not keys, so `load` keeps them.
  `config.logger=` / `config.log_level=` wrap `Logger.instance=` / `Logger.level=`; `Logger.trace` is a no-op for
  loggers without `trace`, and `Logger::Context` tags are only printed by `Logger::SimpleFormatter`.
- **`Cosmo::Engine`** (`lib/cosmo/engine.rb`) — singleton; starts `Job::Processor` and/or `Stream::Processor` sharing
  one `Utils::ThreadPool`. Traps `INT`/`TERM` (graceful shutdown), `TSTP`/`CONT` (quiet / resume fetching), and `USR1`
  (quiet, then exit once in-flight work drains), and `TTIN` (log every thread's backtrace).
- **`Cosmo::Publisher`** (`lib/cosmo/publisher.rb`) — singleton; serializes and publishes stream messages via
  `publish(subject, data, ...)`.
- **`Cosmo::Job::Enqueuer`** (`lib/cosmo/job/enqueuer.rb`) — `enqueue(class_name, args, options, batch:)`, the one
  path a job takes onto its stream, for `perform_async`/`perform_in`/`perform_at` and the ActiveJob adapter. Only
  `Cosmo::Job` passes `batch: Batch.current`; ActiveJob jobs never join a Cosmo batch.
- **`Cosmo::Web`** (`lib/cosmo/web.rb`) — Rack app for the monitoring UI (HTMX), served via `config.ru` or mounted
  (routes match `request.path_info`, which is mount-relative, and `Renderer#url_for` prepends `script_name`). It
  ships **no authentication** — wrap it with your own (Devise `authenticate` / route constraints when
  mounted, `Rack::Auth::Basic` standalone). It also has **no CSRF protection** yet, while exposing
  destructive routes (retry/delete dead jobs, pause streams, delete/run crons).
- **`Cosmo::Heartbeat`** (`lib/cosmo/heartbeat.rb`) — started by `Engine#run`; every 10s writes this process's
  details (`hostname-pid`, IP, cmdline, subscriptions, busy, `running`/`quiet`/`stopping`) to the `cosmo_processes`
  KV bucket via `API::Stats::Processes`. Unregisters on graceful shutdown; a crashed process expires by the bucket's 60s TTL.
- **`Cosmo::Batch`** (`lib/cosmo/batch.rb`) — groups jobs and fires a `:success`/`:complete` callback when the group
  finishes; state lives in `Batch::Counters` (the `_cosmobatches` stream, `max_age` = `config.batches.expiry`, so an
  abandoned batch's counters expire with its KV state) plus a TTL'd KV bucket. Nested batches are created with
  `Batch.new(parent: bid)`.
- **`Cosmo::Services`** (`lib/cosmo/services.rb`) — the service streams Cosmo depends on, built on demand from the
  `Cosmo.configure` settings (never from YAML, since an initializer runs after the CLI loads it): `scheduled` stream +
  consumer (`config.scheduled.enabled`; off → no stream, no scheduler, `perform_in`/crons raise
  `SchedulingDisabledError`), `dead` (`config.dead`: retention, or off → given-up jobs are `term`ed), and the
  `_cosmostats` totals (`API::Stats::Totals`; always on, never expire) and the `_cosmobatches` batch counters,
  all `API::Counter` subclasses. `config.replicas` sizes these and the KV buckets.
  `Services.setup!` runs in `cosmo --setup`; specs get it through `create_streams`.
- **`Cosmo::API::Cron`** (`lib/cosmo/api/cron.rb`) — recurring jobs use **NATS 2.14 server-side message schedules**
  (`Nats-Schedule` headers on a template stored at `cosmo.cron.<target stream>.>`). Every template lives in the
  `scheduled` stream: NATS only lets a schedule fire at a subject its own stream covers, and rejects `discard: new`
  wherever scheduling is enabled, so confining it to one stream leaves the job streams free to pick a discard policy.
  A firing lands back in `scheduled` carrying the `X-Stream`/`X-Subject` headers copied off the template, and
  `Job::Processor#schedule_loop` dispatches it on — the same path delayed jobs take, so a `--no-scheduler` worker
  fires no crons. Nothing to elect a leader for; whatever is deployed in NATS is exactly what the UI shows.
- **`Cosmo::Job::Limit`** (`lib/cosmo/job/limit.rb`) — distributed concurrency limiter; numbered KV slots acquired via
  CAS, auto-expired by `Nats-TTL`.
- **`Cosmo::ActiveJobAdapter`** (`lib/cosmo/active_job/`) — `config.active_job.queue_adapter = :cosmonats`; the
  ActiveJob queue name maps to a Cosmo stream. Wired up automatically inside Rails by `Cosmo::Railtie`. See
  `docs/active_job.md`.
- **Server middleware** (`Config#server_middleware`, `lib/cosmo/middleware/`) — a `Middleware::Chain`, registered via
  `Cosmo.configure { |config| config.server_middleware { |chain| ... } }`, that `Job::Processor#process` invokes as
  `call(job, data, message)` around `perform_job`, inside
  the retry/DLQ rescue. It starts as `[Middleware::Limit, Middleware::Busy, Middleware::Totals, Middleware::Metrics]`: Limit enforces a
  job class's `limit:` (concurrency slots via `Job::Limit`, the duration timeout) and raises `Job::Requeue` while slots
  are taken, which the processor naks with its delay instead of failing the job; Totals counts every execution, retries
  included. Logging and batch notification stay hard-wired in the processor. `perform_sync` and stream processors
  don't run it.
- **Metrics** (`Middleware::Metrics`, `API::Stats::Metrics`, `config.metrics`) — while enabled, the middleware buffers
  per (UTC day, job class) runs, failures, exec time (successes only) and first-delivery wait in memory;
  `Heartbeat#flush` writes them every 10s (and on stop) as `Nats-Incr` counters to the internal `_cosmometrics` stream
  (`max_age` = `config.metrics.retention`, created by `Services.setup!`). Subjects are
  `_cosmometrics.jobs.<YYYYMMDD>.<Class-Name>.<field>` (`::` → `-`, reversible); reads are one batched direct get
  (`Client#last_messages`, `multi_last`). The web UI's Metrics tab (`Web::Chart` draws the SVG) shows only while enabled.
- **Client middleware** (`Config#client_middleware`) — an initially empty `Middleware::Chain` that
  `Job::Enqueuer.enqueue` invokes as `call(job_class_name, payload, stream)` around the publish (so for
  `perform_*` and the ActiveJob adapter, never `perform_sync`). `payload` is the Hash that gets published; not
  yielding stops the publish (`enqueue` returns nil) and releases the batch slot. `stream` is the target stream.
- **Error handlers** (`Config#error_handlers`, `Cosmo.handle_error`) — callables given `(error, context)` for every
  error Cosmo rescues: failed job attempts and rejected messages (`Job::Processor`), failing stream batches
  (`Stream::Processor`, now logged at error level), fetch, scheduler, `retry_in` and limit-slot errors. `context` has
  a `:source` plus what is known there. A raising handler is logged and skipped; `handle_error` itself doesn't log.
- **Sentry** (`lib/cosmo/middleware/sentry.rb`) — `Middleware::Sentry` (transactions only) and
  `Middleware::Sentry::ERROR_HANDLER` (exception capture), not loaded by default (needs `sentry-ruby`): apps
  `require "cosmo/middleware/sentry"` and register both themselves.

---

## Adding Jobs vs Streams

**Jobs** — one-shot tasks:
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
`Stream` classes **auto-register** when `options` is called (`Config.internal[:streams]`). Streams in `app/streams/`
are eagerly loaded by the CLI.

---

## Subject & Stream Naming Conventions

- **Job subjects**: `jobs.<stream_name>.<underscored_class_name>` — e.g. `jobs.default.send_email_job`
- **Dead letter**: `jobs.dead.<underscored_class_name>`
- **Scheduled jobs**: routed through the `:scheduled` stream with headers `X-Execute-At`, `X-Stream`, `X-Subject`.
  A cron firing carries no `X-Execute-At`; the scheduler forwards timestamp as `X-Enqueued-At` so `enqueued_at` on the
  job based on the firing time rather than the dispatch time
- **Stream subjects**: default `<underscored_class_name>.>` — interpolated via Ruby `format(str, name:)`
- Config YAML `subject`/`subjects` fields use `%{name}` format strings interpolated with the stream name (see
  `Config.normalize!`)

---

## Configuration Gotchas

- `max_age` and `duplicate_window` in **YAML are in seconds** — `Config.normalize!` converts to nanoseconds
  automatically.
- `message.nak(delay:)` takes **nanoseconds** directly (e.g. `30_000_000_000` = 30s). `nack` is an alias of `nak`; the
  underlying nats-pure method is `nak`.
- Retry backoff: `attempt**4 + 15` **seconds**, converted with `Config.to_ns` at NAK time
  (`Job::Processor#retry_delay`). Override per job class with the `retry_in: ->(count, exception) { seconds }` option;
  a non-numeric/non-positive return or a raise falls back to the default.
- A job's `retry:` is capped by its consumer's `max_deliver`: exceeding it dead-letters one delivery early with a
  warning rather than stranding the message (`Job::Processor#deliver_cap`).
- `fetch_timeout: 0` or negative is not rejected — `Stream::Processor#fetch_timeout` logs a warning and
  substitutes `Stream::Data::DEFAULTS[:fetch_timeout]` (10s). Job consumers ignore the configured value
  entirely (`Job::Processor#fetch_timeout`).
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

# Other flags: -t/--timeout (shutdown timeout), -v/--version, -h/--help.
# A third command, `actions`, is declared in the CLI but has no processor behind it yet.

# Start monitoring UI
bundle exec puma
```

Spin up NATS for local dev/test:
```bash
docker compose up nats
```

---

## Testing Patterns

- Specs assume a **live NATS connection**; use `destroy_streams` (from `spec/support/global_helpers.rb`) to purge
  streams between tests.
- `RSpec.shared_context "Global helpers"` is included globally; gives `client` and `destroy_streams` helpers.
- Use `perform_sync` to test job logic without NATS.
- Never write specs for the web UI (`lib/cosmo/web/`: controllers, views, assets); verify UI changes by running it.

---

## Singleton Pattern
`Client`, `Config`, `Engine`, `Publisher`, `CLI`, `Job::Limit`, `API::Stats::Totals`, `API::Stats::Busy`, `API::Stats::Processes`, `API::Cron` all use
`@instance ||= new`. Reset between tests if needed by clearing `@instance` via `instance_variable_set`.

---

## Key Files
| Purpose | Path |
|---|---|
| Built-in config defaults (`cosmo --init` copies it; test config at `spec/support/cosmo.yml`) | `lib/cosmo/config/cosmo.yml` |
| Service streams (scheduled, dead, counters) | `lib/cosmo/services.rb` |
| Job mixin + ClassMethods | `lib/cosmo/job.rb` + `lib/cosmo/job/` |
| API base classes (KV bucket, counter, TTL'd registry) | `lib/cosmo/api/{kv,counter,registry}.rb` |
| Dashboard stats built on them (`API::Stats.summary`) | `lib/cosmo/api/stats.rb` + `lib/cosmo/api/stats/` |
| Batch grouping + callbacks | `lib/cosmo/batch.rb` + `lib/cosmo/api/batch.rb` |
| Cron schedules (NATS 2.14) | `lib/cosmo/api/cron.rb` + `lib/cosmo/api/cron/entry.rb` |
| Concurrency limiter | `lib/cosmo/job/limit.rb` |
| ActiveJob adapter + Railtie | `lib/cosmo/active_job/` + `lib/cosmo/railtie.rb` |
| Vendored nats-pure fixes | `lib/cosmo/utils/overrides.rb` |
| Stream mixin + registration | `lib/cosmo/stream.rb` + `lib/cosmo/stream/` |
| Server middleware chain + built-ins | `lib/cosmo/middleware.rb` + `lib/cosmo/middleware/` |
| Engine / signal handling | `lib/cosmo/engine.rb` |
| NATS client wrapper | `lib/cosmo/client.rb` |
| Structured logger | `lib/cosmo/logger.rb` |
| CLI entrypoint | `lib/cosmo/cli.rb` |
| Monitoring Rack app | `lib/cosmo/web.rb` |
| RBS type signatures | `sig/` |
