# Configuration

## Subjects

NATS subjects follow a dot-separated hierarchy (`events.clicks.homepage`).
The `>` wildcard matches everything after that prefix. Think of subjects as topic names — flexible routing with no extra configuration.

## cosmo.yml

`config/cosmo.yml` is optional. Cosmo ships its defaults in
[`lib/cosmo/config/cosmo.yml`](https://github.com/bitsbeam/cosmonats/blob/main/lib/cosmo/config/cosmo.yml) (`cosmo --init` copies it into your project), and your
file is deep-merged over them: keep only what you change. The one list that is not merged is your job streams —
listing any under `setup.jobs` replaces the built-in `default` stream and its consumer:
```yaml
concurrency: 10

stream_config: &stream_config
  storage: file
  retention: workqueue
  duplicate_window: 120 # seconds
  discard: new
  allow_direct: true    # required by the web UI
  num_replicas: 1       # e.g. 3 on a NATS cluster
  subjects: ["jobs.%{name}.>"]

consumer_config: &consumer_config
  ack_policy: explicit
  max_deliver: 30       # keep it above every job class's retry
  max_ack_pending: 20
  max_waiting: 512      # pulls the server parks per consumer, raise it when many idle threads poll one stream
  ack_wait: 60          # seconds
  subject: jobs.%{name}.>

setup:
  jobs:
    critical: { <<: *stream_config }
    default: { <<: *stream_config }
  streams:              # Cosmo::Stream processors are always yours to declare
    events:
      storage: file
      retention: limits
      max_age: 86400
      subjects: ["events.>"]

consumers:
  jobs:
    critical: { <<: *consumer_config, priority: 50 }
    default: { <<: *consumer_config, priority: 15 }
```
`max_age`, `duplicate_window`, and `ack_wait` are in seconds. Without `setup.jobs`, `consumers.jobs.default` still
tunes the built-in consumer (e.g. just `ack_wait: 300`).

`consumers.jobs` can also be a list of groups, e.g. to mirror which streams each worker fleet runs together. It is
flattened on load, so it only organizes the file; a stream may appear in one group only:
```yaml
consumers:
  jobs:
    - critical: { <<: *consumer_config, priority: 50 }
      default: { <<: *consumer_config, priority: 15 }
    - crawlers: { <<: *consumer_config, ack_wait: 1860 }
```

## Service streams

The `scheduled` stream (delayed jobs, crons), the `dead` stream (dead letters), and the stats
counters and KV buckets are Cosmo's own: they are not part of `cosmo.yml`, and `cosmo --setup` creates them next to
yours. Tune them in `Cosmo.configure`:
```ruby
Cosmo.configure do |config|
  config.services.num_replicas = 3   # every service stream and bucket, for a NATS cluster (default 1)
  config.dead.max_age = "14d"        # dead-letter retention: max_age, max_msgs (10_000), max_bytes (-1); default 7d
  config.dead.enabled = false        # drop jobs that give up instead of parking them
  config.scheduled.enabled = false   # no scheduled stream or scheduler: perform_in/perform_at and crons raise
  config.batches.expiry = "1d"       # how long batch tracking data lives (default 3d)
  config.metrics.retention = "90d"   # how long the Metrics tab's per-day numbers are kept (default 30d)
  config.metrics.enabled = false     # record nothing and hide the Metrics tab
end
```
Turning `scheduled` or `dead` off also hides their pages in the web UI. Stats can't be turned off — the web UI
depends on them.

## Ruby configuration

`cosmo.yml` holds streams, consumers, and process settings; `Cosmo.configure` holds what YAML can't
express (loggers, middleware) and Cosmo's service settings. Command-line flags (`-c`, `-t`, `-p`) win over the file.
```ruby
Cosmo.configure do |config|
  config.logger = Rails.logger # any ::Logger; defaults to stdout
  config.log_level = :debug    # COSMO_LOG_LEVEL, when set, wins
end
```
Cosmo leaves a custom logger's formatter alone, so its lines lack Cosmo's `jid`/`elapsed` context unless you set
`logger.formatter = Cosmo::Logger::SimpleFormatter.new`. Trace output is dropped for loggers without a `trace` level.

## Environment variables

| Variable                   | Default                              | Description                                                                         |
|----------------------------|--------------------------------------|-------------------------------------------------------------------------------------|
| `NATS_URL`                 | `nats://localhost:4222`              | NATS server(s) to connect to                                                        |
| `COSMO_LOG_LEVEL`          | `info`                               | `trace`, `debug`, `info`, `warn`, `error` or `fatal`                                |
| `COSMO_CLIENT_NAME`        | `cosmo-<program>-<host>-<pid>`       | NATS connection name, shown in `nats server report connections` and `/connz`        |
| `COSMO_JS_TIMEOUT`         | `5`                                  | JetStream API timeout in seconds; raise it for the web UI on a busy server          |
| `COSMO_CONNECT_TIMEOUT`    | `2`                                  | NATS TCP connect timeout in seconds                                                 |
| `NATS_MAX_RECONNECT_ATTEMPTS` | `-1`                              | Reconnect attempts before giving up on NATS; `-1` keeps trying through any outage   |
| `COSMO_JOBS_STREAMS`       | all configured                       | Comma-separated job streams to subscribe to, when `--streams`/`--stream` isn't given |
| `COSMO_JOBS_FETCH_TIMEOUT` | `0.1`                                | Seconds a jobs worker waits on each fetch                                           |
| `COSMO_WEB_POLL_INTERVAL`  | `5`                                  | Web UI auto-refresh interval in seconds                                             |
| `COSMO_WEB_CACHE_TTL`      | `2`                                  | Seconds the web UI shares a refresh between viewers; `0` turns sharing off          |
