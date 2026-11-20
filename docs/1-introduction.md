# Introduction

Background jobs + real-time event streaming for Ruby — unified, in one gem, backed by NATS.
No Redis. No DB polling. Disk-backed, horizontally scalable — no message is ever silently dropped.

## Why NATS?

Most background job libraries use Redis or Postgres — tools that were never designed for this. Think of NATS as Redis — but Redis is KV first then messaging;
NATS is messaging first, then KV. What NATS is:

- **~20 MB binary, ~10 MB RAM at idle** Trivial to run anywhere.
- **Disk-backed persistent streams** Messages survive restarts, don't require RAM to fit.
- **True horizontal clustering** Lose a node — other nodes take over, zero message loss.
- **Multilingual** Official clients for Ruby, Go, Python, Rust, Java, .NET, and more. Any service can publish or consume.

One NATS server replaces your message broker, job queue, and KV store — with lower operational overhead.

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


## Killer features

### Jobs + Streams, unified in one gem

Most Ruby gems handle exactly that — background jobs. If you also need to consume a continuous event feed, that's a second system, second config, second set of
worker processes, second Dockerfile entry. Cosmonats is the only Ruby gem with a first-class `Job` primitive *and* a first-class `Stream` primitive, sharing
one server, one config, one CLI, one monitoring endpoint.

### Message replay and time-travel debugging

NATS persists messages to disk and lets any consumer rewind to any point — beginning of time, a specific timestamp, or only new messages.

- **Incident recovery** — your pipeline crashed for 3 hours. Replay from the crash timestamp.
- **New consumer bootstrap** — a new service needs historical events. Start it from the beginning.
- **Bug reproduction** — replay the exact sequence of messages that caused a production issue.

### Multi-datacenter queues, natively

NATS has a first-class cluster + leaf-node architecture for geo-distribution. Spanning multiple regions or datacenters is a config block — not a separate
product or a third-party replication tool. NATS was built for edge computing, IoT, and satellite communication — multi-DC is a first-class concern, not an
afterthought.

### Transport-level deduplication + built-in KV

NATS deduplicates messages at the **broker** — same-ID messages within the configured window are dropped before they ever reach a worker. No uniqueness gems,
no advisory locks, no extra round-trips. It also ships a built-in Key/Value store usable for distributed locks and rate limiting — no Redis, no Memcached,
nothing else to run.


## Features

### Job processing

- **Familiar API** — `perform_async`, `perform_in`, `perform_at`
- **Priority queues** — critical, high, default, low with weighted round-robin
- **Scheduled jobs** — execute at a specific time or after a delay
- **Automatic retries** — exponential backoff, configurable attempts
- **Dead letter queue** — capture permanently failed jobs
- **Job uniqueness** — prevent duplicate execution
- **Concurrency limits** — cap simultaneous executions per class or per key
- **Cron scheduling** — recurring jobs manageable live from the web UI
- **Batches** — group jobs and fire a callback once the whole group finishes, including nested batches

### Stream processing

- **Real-time event streams** — process continuous data feeds
- **Batch processing** — handle multiple messages in one go
- **Message replay** — reprocess from any point in time
- **Consumer groups** — load-balanced across workers
- **Custom serialization** — JSON, MessagePack, Protobuf
- **Pause / resume** — stop and restart a stream's processing without losing its position
