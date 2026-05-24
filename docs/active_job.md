# Active Job

## Setup

Set the queue adapter in `config/application.rb`:

```ruby
config.active_job.queue_adapter = :cosmonats
```

That's it. The Railtie that ships with `cosmonats` registers the `:cosmonats` adapter and autoloads `config/cosmo.yml`.

## Queues

Use `queue_as` exactly as you would with any other ActiveJob backend:

```ruby
class ProcessPaymentJob < ApplicationJob
  queue_as :critical

  def perform(order_id)
    Order.find(order_id).charge!
  end
end
```

Each queue name maps to a NATS **stream** of the same name. Declare every stream you plan to use in your `config/cosmo.yml`:

```yaml
stream_config: &stream_config
  storage: file
  retention: workqueue
  duplicate_window: 120
  discard: old
  allow_direct: true
  subjects:
    - jobs.%{name}.>

consumer_config: &consumer_config
  ack_policy: explicit
  max_deliver: 10
  max_ack_pending: 20
  ack_wait: 60
  subject: jobs.%{name}.>

consumers:
  jobs:
    default:
      <<: *consumer_config
    critical:
      <<: *consumer_config
      priority: 5       # polled more often than default
    mailers:
      <<: *consumer_config
    scheduled:          # required for set(wait:) / set(wait_until:)
      <<: *consumer_config
      max_deliver: 1
      max_ack_pending: 100
      ack_wait: 10

setup:
  jobs:
    default:
      <<: *stream_config
    critical:
      <<: *stream_config
    mailers:
      <<: *stream_config
    scheduled:
      <<: *stream_config
    dead:               # dead-letter queue
      <<: *stream_config
      retention: limits
      max_msgs: 10000
      max_age: 604800   # 7 days

production:
  concurrency: 10
```

Provision streams (safe to run on every deploy):

```bash
cosmo -S
```

## Delayed jobs

`set(wait:)` and `set(wait_until:)` are fully supported via the built-in `:scheduled` stream.
No extra configuration is needed beyond declaring the stream above.

```ruby
ProcessPaymentJob.set(wait: 5.minutes).perform_later(order.id)
ProcessPaymentJob.set(wait_until: Date.tomorrow.noon).perform_later(order.id)
```

## Cosmo-specific options

`cosmo_options` is available on every ActiveJob class. Use it to set NATS-level retry and dead-letter behavior:

```ruby
class ProcessPaymentJob < ApplicationJob
  queue_as :critical
  cosmo_options retry: 5, dead: true

  def perform(order_id)
    Order.find(order_id).charge!
  end
end
```

| Option    | Default        | Description                                                                 |
|-----------|----------------|-----------------------------------------------------------------------------|
| `retry:`  | `3`            | How many times Cosmonats retries the job at the NATS level before giving up |
| `dead:`   | `true`         | Move the message to the dead-letter stream after retries are exhausted      |
| `stream:` | _(queue_name)_ | Override the NATS stream regardless of `queue_as`                           |

Options are inherited and can be overridden in subclasses:

```ruby
class UrgentPaymentJob < ProcessPaymentJob
  cosmo_options retry: 1   # inherits dead: true, overrides retry
end
```

> **`retry_on` vs `cosmo_options retry:`** — these are two independent retry
> mechanisms at different layers:
>
> - `retry_on` is handled entirely inside `Executor#perform` by ActiveJob before
>   the method returns. From Cosmonats' perspective the job *succeeded* — the
>   message is acked and removed from the stream. ActiveJob re-enqueues a brand
>   new message for each attempt.
> - `cosmo_options retry:` tells Cosmonats how many times to redeliver the
>   *same* NATS message when `Executor#perform` raises an unhandled exception
>   (i.e. one not caught by `retry_on`).
>
> In practice: use `retry_on` for expected, recoverable errors (network blips,
> rate limits) and `cosmo_options retry:` as the last-resort safety net for
> anything unexpected. Avoid setting both for the same error class, or you will
> get retries multiplied across both layers.

## Running the worker

The Cosmo worker is a separate process. In a Rails app the CLI auto-discovers
`config/boot.rb` and `config/environment.rb`:

```bash
bundle exec cosmo -C config/cosmo.yml -c 10 jobs
```

| Flag                  | Description                                                 |
|-----------------------|-------------------------------------------------------------|
| `-C config/cosmo.yml` | Cosmo config file                                           |
| `-c 10`               | Worker threads                                              |
| `jobs`                | Run job processor only (omit to also run stream processors) |

**Procfile**:

```
web:    bundle exec puma -C config/puma.rb
worker: bundle exec cosmo -C config/cosmo.yml -c 5 jobs
```

## Testing

Use the built-in `:test` adapter in your test suite:

```ruby
# spec/rails_helper.rb  (or test/test_helper.rb)
config.active_job.queue_adapter = :test
```

With the test adapter, `perform_later` enqueues the job into an in-memory queue
that you can assert against:

```ruby
expect { ProcessPaymentJob.perform_later(order.id) }
  .to have_enqueued_job(ProcessPaymentJob).with(order.id)
```

To run job logic synchronously without any queue:

```ruby
ProcessPaymentJob.perform_now(order.id)
```

## Dead-letter queue (DLQ)

When a job exhausts all retries, Cosmo moves it to the `dead` stream under the
subject `jobs.dead.cosmo-active_job_adapter-executor`. Inspect failed jobs with
the NATS CLI or the built-in monitoring UI:

```bash
nats stream view dead
```
