# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Cosmo.configure` with `config.server_middleware`: a middleware chain around every job execution
- `config.logger = ...` and `config.log_level = ...` in `Cosmo.configure`; a logger without `trace` no longer raises
- Built-in config defaults: Cosmo runs without `config/cosmo.yml`, and a user file is deep-merged over the defaults;
  `cosmo --init` writes them into the project
- `config.replicas`, `config.dead` (retention, or off), `config.scheduled.enabled`, and `config.batches.expiry` in
  `Cosmo.configure` for Cosmo's own service streams

### Changed

- **Breaking:** the `scheduled` and `dead` streams are Cosmo's, created by `cosmo --setup`: listing them under
  `setup.jobs`/`consumers.jobs` raises `ConfigError`, as does `batch_expiry` (now `config.batches.expiry`). Listing
  your own `setup.jobs` replaces the built-in `default` stream
- **Breaking:** the `dead` stream uses `workqueue` retention instead of `limits`. NATS can't change retention in place,
  so delete an existing one (`nats stream rm dead`, dropping its jobs) before `cosmo --setup`

- The Web UI's Failed total counts every failed execution, retries included, instead of only jobs that gave up
- Jobs are enqueued through `Cosmo::Job::Enqueuer.enqueue`; `Publisher.publish_job`, `Publisher.publish_batch`, and
  `Job::Data#to_args` are removed, and `Job::Data#subject` returns the subject as a string
- Sentry is the `Cosmo::Middleware::Sentry` middleware: `require "cosmo/middleware/sentry"` and add it to the chain;
  `cosmo/sentry/auto` and `Cosmo::Sentry::JobProcessorMiddleware` are removed

## [0.7.0] - 2026-10-06

### Added

- Processes page in the Web UI listing every live worker with its host, IP, command line, subscriptions,
  busy threads, and state, fed by a heartbeat into the `cosmo_processes` KV bucket
- `Cosmo::Client` names its NATS connection (`cosmo-<program>-<host>-<pid>`), so a process can be
  identified in `nats server report connections` / `/connz` without cross-referencing host IPs.
  Override with `COSMO_CLIENT_NAME`
- `COSMO_JS_TIMEOUT` and `COSMO_CONNECT_TIMEOUT` make the JetStream API and TCP connect timeouts
  configurable. Defaults are unchanged (5s / 2s, as in nats-pure); raise the former per-process
  where waiting beats failing -- the web UI on a busy server -- and leave it alone for workers
- `COSMO_WEB_POLL_INTERVAL` sets the web UI's htmx auto-refresh interval (default 5s, unchanged).
- Enqueued jobs can be removed one by one from the web UI: each row has a Remove button backed by
  `DELETE /jobs/enqueued/<seq>?stream_name=<stream>`, which drops that message from the stream
- `kill -TTIN <pid>` logs every thread's backtrace at WARN, tagged with the same `tid` as regular log
  lines, so a stuck worker can be diagnosed without restarting it
- `kill -TSTP <pid>` quiets a worker (no new jobs are fetched, in-flight work finishes) and `kill -CONT <pid>`
  resumes it; `kill -USR1 <pid>` quiets it and exits once in-flight work drains
- Jobs workers can pick their streams with `--streams a,b` / `--stream a` or `COSMO_JOBS_STREAMS`; unknown names
  abort before boot. `--no-scheduler` keeps a worker off scheduled dispatch, so it fires no delayed jobs or crons
- `Cosmo::HTTPServer`: `-p/--http-port` (or `http.port`) serves `GET /health` (200 when the engine runs and NATS
  is connected, 503 otherwise) and `GET /ping` (liveness)
- `Cosmo::Batch.new(bid:)` takes your own batch id instead of a generated one
- The busy jobs page is paginated, shows each job's delivery attempt, and can stop live polling

### Changed

- Relicensed from LGPL-3.0 to MIT
- Dashboard stats live under `API::Stats` on top of base classes: `API::Busy` is now `API::Stats::Busy`,
  and `API::Counter.instance`/`#with` moved to `API::Stats::Totals`
- nats-pure is capped below 2.7, and Cosmo's nats-pure patches skip themselves where nats-pure already has the fix
- `rack`, `rackup` and `webrick` are no longer runtime dependencies: add `rack` to your Gemfile for the web UI,
  and `rack`, `rackup` and `webrick` for `Cosmo::HTTPServer`

### Fixed

- The `_cosmostats` counters stream kept every increment forever (one message per processed job). It now keeps
  only the latest message per counter (`max_msgs_per_subject: 1`); `cosmo --setup` applies this to existing
  streams, trimming them without changing the totals
- A cron job's `enqueued_at` is the time NATS fired the schedule again, not the time the scheduler
  dispatched it on. The firing's timestamp is forwarded as `X-Enqueued-At` across the re-publish, so a
  job that derives anything from `enqueued_at` is unaffected by a backlogged or restarted worker
- Dead jobs record the exception class, message and backtrace, so the web UI's Error column is no longer empty.
  The dead jobs page shows the stream a job came from and keeps expanded errors open
- `API::KV#size` stopped at 25 keys, so the web UI showed at most 25 busy jobs
- The dashboard's Scheduled count included cron templates, which the scheduled jobs page doesn't list
- The scheduler dropped a job's headers when dispatching it from the scheduled stream
- Several idle threads polling the same stream advanced its fetch backoff once each per round, reaching the
  maximum backoff after a few rounds; it now advances once per round
- `Message#nack` in stream processors raised `NoMethodError`; it is now an alias of nats-pure's `nak`
- JSON parsing works with json 3

## [0.6.0] - 2026-08-07

### Added

- `TRACE` log level, below `DEBUG` — opt in with `COSMO_LOG_LEVEL=trace`
- `Cosmo::Client#subscribe` creates an ephemeral (server-named) pull consumer when called with `consumer_name: nil`
- `Cosmo::Client#delete_consumer` — explicit server-side consumer deletion

### Fixed

- Vendored a fix for an upstream `nats-pure` bug (`NATS::JetStream::PullSubscription#fetch` raised
  `TypeError: nil can't be coerced into Float` when called concurrently on the same subscription.
  `Cosmo::Processor` no longer needs to serialize fetches per stream through a mutex to work around it,
  so the existing priority-weighted consumer list now fetches in genuine parallel for busy streams,
  as originally intended
- Bug in that same vendored `#fetch`: a message fetched right as its deadline was perceived
  to have passed got silently discarded instead of returned, occasionally dropping a job for good
  under concurrent fetches on one subscription

### Changed

- Sample `cosmo.yml`/README's scheduled-job consumer `max_deliver` raised from 1 to 5

## [0.5.1] - 2026-08-04

### Fixed

- Pause-stream spec for `Cosmo::Stream::Processor` no longer raises `TypeError`; it now parses `STREAMS_PAUSED_IDLE_SLEEP` via `Cosmo::Utils::Duration.parse` before adding to it, instead of treating the duration string as a Float

## [0.5.0] - 2026-08-04

### Added

- `Cosmo::Batch` — group jobs and fire a `:success`/`:complete` callback once the whole group finishes, including nested batches created from within a running job. The registered class is plain Ruby (`on_success(status, opts)`/`on_complete(status, opts)`), dispatched via an internal `Batch::Callback` job on the normal worker pool
- `Cosmo::API::Batch` read-model and a **Batches** tab in the web UI, listing open/finished batches with pending/succeeded/failed counts
- `Cosmo::API::KV#create` for CAS-if-absent writes without per-message TTL
- `Cosmo::API::Counter#increment`/`#decrement` accept `msg_id:` to make a redelivered notification idempotent (backed by the counter stream's `duplicate_window`)
- `retry: false` is now accepted as an alias for `retry: 0` (no retries), for both `Cosmo::Job` and the ActiveJob adapter's `cosmo_options`
- `retry_in` option to customize the delay before a failed job is redelivered
- Parse human-readable time duration to seconds

### Fixed

- A transient error while dispatching an overdue scheduled job (e.g. a slow JetStream publish) no longer kills the scheduler thread; the message is logged and NAK'd instead, so scheduled-job dispatch keeps running
- `max_retries` in `cosmo.yml` is now actually used as the default retry count for jobs that don't set their own `retry:` (previously it was inert)
- A job's `retry:` exceeding its stream's consumer `max_deliver` no longer leaves the message stranded in the stream forever; it's now capped and dead-lettered (or terminated) a delivery early, with a warning logged

### Changed

- Sample `cosmo.yml`'s `max_deliver` raised from 10 to 30 per tier, and documented as a coarse safety ceiling against runaway redelivery rather than a per-job retry budget

## [0.4.3] - 2026-07-30

### Added

- `Cosmo::Job` instances now expose `enqueued_at`, `attempt`, and `scheduled_by`, populated from the NATS message's metadata/headers alongside the existing `jid`

## [0.4.2] - 2026-07-29

### Added

- `retry_in` option for concurrency-limited jobs, to control the NAK delay when a slot can't be acquired (defaults to half of `duration`)
- Page-number pagination with gap markers (`:gap`) for the enqueued jobs list, plus improved navigation
- README examples for cron, concurrency limits, custom serializers, and integrations

### Changed

- `Cosmo::Api::Kv#set` now uses a single CAS publish instead of a get-then-retry sequence
- Concurrency slots are released via a new tombstone-free `Kv#erase`, so a released slot is indistinguishable from one reclaimed by TTL expiry

## [0.4.1] - 2026-07-24

### Added

- Sentry integration for error tracking, with improved transaction handling
- Global loading spinner with htmx indicator for job stats links
- Optimized stream iteration with gap handling and sequence skipping

### Fixed

- NATS timeout errors in the client and stream retry methods
- Integer conversion for cron schedule count

## [0.4.0] - 2026-06-15

### Added

- Cron job scheduling

### Fixed

- `NoMethodError: undefined method 'map' for nil`

## [0.3.0] - 2026-05-22

### Added

- Pause/unpause streams, tracked per-stream via metadata
- Backoff for empty stream fetches
- Initial ActiveJob integration
- Hide KV and system buckets in the web UI
- Distributed concurrency limiter with per-message TTL
- README improvements: badges, GIF walkthrough, `docker run` command for NATS

### Changed

- Moved `work_loop` into a shared base class
- Config no longer ships with defaults; it must be copied or created explicitly

### Fixed

- Missing htmx assets in the repo
- Timeout fetching messages in a busy environment where a message can disappear quickly
- HTMX poller pagination
- Path comparison in `current_page?` and `referrer?`
- Concurrent deletions in the stream processing loop

## [0.2.0] - 2026-04-30

### Added

- Web UI
- Stats page
- Integration tests for `Cosmo::Job::Processor`

### Fixed

- Same-stream fetch raising `TypeError: nil can't be coerced into Float` inside nats-pure
- Lint violations

## [0.1.4] - 2026-02-26

### Added

- `fetch_timeout` option, with improved error handling in message fetching
- Logging for NATS connection establishment

## [0.1.3] - 2026-02-20

### Added

- Debug logging for message fetching and processing

## [0.1.2] - 2026-02-18

### Added

- CLI flags passed through to config
- Only classes that called `options` are registered as consumers

### Changed

- Consumers are stored in an array instead of a hash

### Fixed

- Booting the app when creating streams

## [0.1.1] - 2026-02-17

### Added

- Engine singleton
- `start_position` option for streams
- Logger and logging statements throughout
- CLI flags, commands, and options
- Dedicated processor execution
- Additional metadata in message processing
- Application boot support, requiring Ruby files from default or configured paths
- `processors` option for streams
- Test suite and CI configuration
- RBS type signatures

### Changed

- Refactored stream processing

### Fixed

- Environment variable loading when creating a client
- Config left non-empty before a value is set
- Shutdown when no processors are running

## [0.1.0] - 2026-01-04

### Added

- Initial release: background jobs and stream processing for Ruby, backed by NATS JetStream.

[0.7.0]: https://github.com/bitsbeam/cosmonats/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/bitsbeam/cosmonats/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/bitsbeam/cosmonats/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/bitsbeam/cosmonats/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/bitsbeam/cosmonats/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/bitsbeam/cosmonats/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/bitsbeam/cosmonats/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/bitsbeam/cosmonats/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bitsbeam/cosmonats/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/bitsbeam/cosmonats/compare/v0.1.4...v0.2.0
[0.1.4]: https://github.com/bitsbeam/cosmonats/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/bitsbeam/cosmonats/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/bitsbeam/cosmonats/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/bitsbeam/cosmonats/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bitsbeam/cosmonats/releases/tag/v0.1.0
