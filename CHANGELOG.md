# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Vendored a fix for an upstream `nats-pure` bug (`NATS::JetStream::PullSubscription#fetch` raised
  `TypeError: nil can't be coerced into Float` when called concurrently on the same subscription.
  `Cosmo::Processor` no longer needs to serialize fetches per stream through a mutex to work around it,
  so the existing priority-weighted consumer list now fetches in genuine parallel for busy streams,
  as originally intended

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
