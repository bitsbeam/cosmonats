# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
