# Middleware

## Server middleware

Every job execution on a worker runs through the server middleware chain. A middleware gets the job instance (`nil`
when class can't be loaded), its parsed payload, and the NATS message, and yields to run the rest of the chain:
```ruby
class TimingMiddleware
  def initialize(threshold:)
    @threshold = threshold
  end

  def call(job, data, message)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    job.logger.warn("#{data[:class]} took #{elapsed.round(2)}s on #{message.metadata.stream}") if elapsed > @threshold
  end
end

Cosmo.configure do |config|
  config.server_middleware do |chain|
    chain.add TimingMiddleware, threshold: 5
  end
end
```
Register middleware at boot, before workers start (e.g. in a Rails initializer; loading `cosmo.yml` afterwards keeps
it). The chain starts with Cosmo's required middleware: `Cosmo::Middleware::Limit` (a job class's `limit:`
option), `Cosmo::Middleware::Totals` (processed/failed counts,
one per execution), and `Cosmo::Middleware::Metrics` (the Metrics tab). `add` appends innermost, after them; `prepend`, `insert_before`, `insert_after`, and `remove`
reorder the chain, so moving or removing the built-ins is at your own risk.
A middleware that raises sends the job through the usual retry/DLQ path, and one that doesn't yield skips the job
and acks it. To put a job back for later instead, raise `Cosmo::Job::Requeue.new(delay_in_seconds)`: the job is
redelivered without failing, though the redelivery still counts toward its `retry` and `max_deliver`.
A fresh instance is built for every job. `perform_sync` doesn't run the chain.

## Client middleware

The client chain runs where a job is enqueued (`perform_async`, `perform_in`, `perform_at`, `perform_bulk`, and
the ActiveJob adapter), around the publish; for `perform_bulk`, yielding marks the job for its chunk's publish. It starts empty, and a middleware gets the job class name, the payload Hash that will be
published, and the stream the job runs on:
```ruby
class RequestIdMiddleware
  def call(_job_class, payload, _stream)
    payload[:request_id] = Current.request_id
    yield
  end
end

Cosmo.configure do |config|
  config.client_middleware { |chain| chain.add RequestIdMiddleware }
end
```
Not yielding stops the publish: `perform_async` returns `nil`, and a batch the job was joining doesn't wait for it.
