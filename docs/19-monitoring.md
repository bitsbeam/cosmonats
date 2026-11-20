# Monitoring

## Web UI

Mount `Cosmo::Web` (see [Installation](2-installation.md)) for a live, htmx-powered dashboard with a
light, dark, or automatic (system) theme. Fonts and assets are bundled, so it loads nothing from a CDN:
- **Overview** — processed, failed, busy, enqueued, retries, scheduled and dead totals; a 7- or 30-day throughput
  chart of successful and failed runs; a grid of every worker thread, busy ones colored by stream; the queues; and the
  a sample of the jobs running right now
- **Jobs** — each job queue with its size, busy jobs and redeliveries, paused and resumed in place; then busy,
  enqueued (per queue), scheduled and dead jobs, with retry and delete for dead ones and their error and backtrace
- **Processes** — every live worker (idle ones included): host, pid, IP, NATS connection name, command line,
  subscribed streams, busy/concurrency, running/quiet/stopping state, memory, NATS RTT and reconnects. Each worker
  beats into the `_cosmoprocesses` KV bucket every 10s, and the jobs it's running into `_cosmojobs`; a crashed worker
  drops out within 60s. Busy jobs come from those heartbeats, so they show up to 10s late, and a job shorter than that
  may not show at all. The page reads only the processes it shows, and every count is answered by NATS from the keys.
- **Streams** — every stream with its subjects, messages, size, retention and replicas, its consumers' pending,
  ack-pending and redelivered counts, and pause/resume
- **Crons** — every schedule deployed in NATS, with run-now and delete
- **Batches** — open and finished batches with their progress, succeeded/failed/pending counts and callbacks
- **Metrics** — per job class over today, 7, or 30 days: runs, failures, average execution time (successful runs), and
  average wait from enqueue to first delivery, plus a per-day chart of runs and average execution time. Recorded by
  `Cosmo::Middleware::Metrics`, flushed by every worker's heartbeat into the internal `_cosmometrics` counters stream;
  turn it off with `config.metrics.enabled = false`

## Job ID links

Every job ID in the Jobs tables can link out, e.g. to the job's logs in Grafana. Give
`config.web.jid_link` a URL template, whose `%{jid}`, `%{class}` and `%{stream}` are filled in URL-escaped (any other
`%` in it is left as is), or a callable given the job's payload (`:jid`, `:class`, `:args`, ... and `:stream`) that
returns the URL, or `nil` to keep that one as plain text. Links open in a new tab; only `http(s)` URLs are linked, and a
raising callable falls back to plain text:

```ruby
Cosmo.configure do |config|
  config.web.jid_link = "https://grafana.example.com/d/jobs/cosmo?var-jid=%{jid}&var-class=%{class}"
  # or
  config.web.jid_link = lambda do |job|
    "https://grafana.example.com/explore?left=" + ERB::Util.url_encode(
      { queries: [{ expr: %({app="worker"} |= "jid=#{job[:jid]}") }], range: { from: "now-7d", to: "now" } }.to_json
    )
  end
end
```

## Batch ID links

`config.web.bid_link` does the same for batch IDs on the Batches page: a URL template with `%{bid}`
and `%{parent_id}`, or a callable given `:bid`, `:parent_id` and `:description`.

## Refreshing

Each panel refreshes `COSMO_WEB_POLL_INTERVAL` seconds after its previous response, never on top of one still
running, backs off while refreshes fail, and pauses in a hidden tab. Identical refreshes from several viewers share a
single NATS read for `COSMO_WEB_CACHE_TTL` seconds, and while NATS is unreachable the UI answers at once instead of
holding your app server's threads.

## Structured logs
```
2026-01-23T10:15:30.123Z INFO pid=12345 tid=abc jid=def: start
2026-01-23T10:15:32.456Z INFO pid=12345 tid=abc jid=def elapsed=2.333: done
```

## Stream metrics
```ruby
client = Cosmo::Client.instance
info = client.stream_info("default")

info.state.messages       # Total messages
info.state.bytes          # Total bytes
info.state.consumer_count # Number of consumers
```

## Prometheus

NATS exposes metrics at `:8222/metrics`:
- `jetstream_server_store_msgs` — Messages in stream
- `jetstream_consumer_delivered_msgs` — Delivered messages
- `jetstream_consumer_ack_pending` — Pending acknowledgments
