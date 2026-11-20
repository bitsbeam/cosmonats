# CLI

```bash
cosmo -C config/cosmo.yml --setup                     # Create streams in NATS (idempotent)
cosmo -C config/cosmo.yml -c 20 -r ./app/jobs jobs    # Jobs only
cosmo -C config/cosmo.yml -c 20 streams               # Streams only
cosmo -C config/cosmo.yml -c 20                       # Both
cosmo -C config/cosmo.yml jobs --streams default,high # Jobs, limited to these streams
cosmo -C config/cosmo.yml jobs --stream critical      # Jobs, limited to one stream
cosmo -C config/cosmo.yml jobs --no-scheduler         # Jobs, without dispatching scheduled jobs
COSMO_JOBS_STREAMS=default,high cosmo jobs            # Same filter, without touching the command line
```

Each selected stream gets its own durable consumer, named `consumer-<stream>`. Every process that subscribes to a stream
pulls from that same consumer, so running a dedicated fleet per stream splits the work instead of duplicating it.
The `scheduled` stream is a service stream: it is always dispatched, and naming it in `--streams` selects nothing, use
`--no-scheduler` on workers that should not dispatch scheduled jobs. Unknown stream names abort the process.

## Global flags

They go before the command.

| Flag                    | Description                          | Example               |
|-------------------------|---------------------------------------|-----------------------|
| `-C, --config PATH`     | Config file path                      | `-C config/cosmo.yml` |
| `-c, --concurrency INT` | Worker threads                        | `-c 20`               |
| `-r, --require PATH`    | Auto-require directory                | `-r ./app/jobs`       |
| `-t, --timeout NUM`     | Shutdown timeout (sec)                | `-t 60`               |
| `-p, --http-port INT`   | Serve `/health` and `/ping` on a port | `-p 9090`             |
| `-S, --setup`           | Setup streams & sync cron, then exit  | `--setup`             |
| `--no-cron`             | With `--setup`, skip syncing cron schedules | `--setup --no-cron` |
| `--init`                | Write `config/cosmo.yml` with the defaults, then exit | `--init`  |
| `-v, --version`         | Print version and exit                | `--version`           |
| `-h, --help`            | Show help and exit                    | `--help`               |

## `jobs` options

| Flag                    | Description                                                       | Example                        |
|-------------------------|--------------------------------------------------------------------|---------------------------------|
| `--streams NAMES`       | Only subscribe to these job streams, instead of all configured ones | `--streams default,high`      |
| `--stream NAME`         | Same as `--streams`, for a single stream                           | `--stream default`             |
| `--[no-]scheduler`      | Dispatch scheduled jobs (default: yes)                             | `--no-scheduler`               |
| `--subject NAME`        | Job's subject                                                      | `--subject jobs.default.foo`   |

`--streams`/`--stream` also read from `COSMO_JOBS_STREAMS` (comma-separated) when neither flag is given.

## `streams` options

`--stream`/`--subject`/`--consumer_name`/`--batch_size` apply only when running a single processor; ignored once `--processors` selects more than one.

| Flag                     | Description                          | Example                         |
|--------------------------|---------------------------------------|---------------------------------|
| `--processors NAMES`     | Only run these stream processor classes | `--processors OrderProcessor` |
| `--stream NAME`          | Stream name                          | `--stream orders`              |
| `--subject NAME`         | Subject name                         | `--subject orders.created`     |
| `--consumer_name NAME`   | Consumer name                        | `--consumer_name orders-consumer` |
| `--batch_size NUM`       | Messages per fetch batch             | `--batch_size 50`               |


## Signals

| Signal           | Effect                                                                                     |
|------------------|--------------------------------------------------------------------------------------------|
| `INT`, `TERM`    | Graceful shutdown: stop fetching, wait up to `--timeout` seconds for in-flight work, exit  |
| `TSTP`           | Quiet: stop fetching new work, keep running in-flight work                                 |
| `CONT`           | Resume fetching after `TSTP`                                                               |
| `USR1`           | Quiet, then exit once in-flight work drains                                                |
| `TTIN`           | Log every thread's backtrace at `WARN`, tagged with the same `tid` as regular log lines     |

```bash
kill -TSTP <pid>  # before a deploy: let the old worker finish what it has
kill -TTIN <pid>  # a worker looks stuck: see what each thread is doing
```

The worker's state (`running`, `quiet`, `stopping`) is shown on the web UI's Processes list.

## Health check

Pass `-p/--http-port` (or set `http.port` in the config) to start a small WEBrick HTTP server alongside the workers.
It needs the optional `rack` and `webrick` gems (see [Installation](2-installation.md)); without a port they're never loaded.

```yaml
http:
  port: 9090
  host: 0.0.0.0 # default
```

`GET /health` returns `200` when processors are running and NATS is connected, `503` otherwise:

```bash
curl localhost:9090/health
# {"status":"ok","checks":{"engine":true,"nats":true}}
```

`GET /ping` always returns `200 pong` without checking anything, handy as a liveness probe (use `/health` for readiness):

```bash
curl localhost:9090/ping
# pong
```
