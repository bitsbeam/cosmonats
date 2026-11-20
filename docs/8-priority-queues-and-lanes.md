# Priority queues and lanes

## Priority queues

Each job consumer in `cosmo.yml` takes a `priority:`. Workers poll streams in weighted round-robin, so a stream with a
higher number is polled more often:

```yaml
consumers:
  jobs:
    critical: { <<: *consumer_config, priority: 50 }
    default: { <<: *consumer_config, priority: 15 }
```

A job picks its priority through the stream it runs on:

```ruby
class UrgentJob
  include Cosmo::Job
  options stream: :critical  # priority: 50 in config — polled most frequently
end
```

## Lanes

A stream is FIFO, so 30k jobs of one batch hold back every job enqueued after them. `lanes` splits a stream between
several consumers, `consumer-<stream>-lane-<n>`, each filtering `jobs.<stream>.lane-<n>.>`, that workers poll in turn:

```yaml
consumers:
  jobs:
    crawlers: { <<: *consumer_config, priority: 30, lanes: 8 }
```

A job's lane is its `lane:` option (an Integer, or any key hashed into one), else its batch, so a batch keeps to one
lane, else its jid. The stream's `priority` weighs all its lanes together, and `max_ack_pending` applies per lane.

```ruby
CrawlJob.set(lane: tenant.id).perform_async(url)
```

The lane is part of the subject, so every process that enqueues needs the same config (the Railtie loads it). Crons and
delayed jobs go through the `scheduled` stream, which has no lanes: the scheduler puts each cron firing on a lane when it
dispatches it, and a delayed job keeps the lane it was enqueued with. On a `workqueue` stream, the old `consumer-<stream>` overlaps the lanes'
filters: drain it and delete it before you turn lanes on. Adding lanes is safe; drain a stream before removing some, as
jobs left on a dropped lane are never fetched.
