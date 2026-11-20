# Error handling

```ruby
class ResilientJob
  include Cosmo::Job
  options retry: 5, dead: true

  def perform(data)
    process_data(data)
  rescue RetryableError => e
    logger.warn "Retryable: #{e.message}"
    raise  # Will retry with exponential backoff
  rescue FatalError => e
    logger.error "Fatal: #{e.message}"
    # Don't raise — won't retry, won't go to DLQ
  end
end
```

## Retry delay

By default, a failed job is redelivered after `attempt**4 + 15` seconds. Override that per job class
with `retry_in`, given the 1-based attempt count and the exception that was raised:
```ruby
class ThrottledApiJob
  include Cosmo::Job
  options retry: 5, retry_in: ->(count, exception) { exception.is_a?(RateLimitedError) ? 60 : count * 10 }

  def perform(...)
    # ...
  end
end
```
If the proc returns something non-numeric/non-positive, or raises, the default backoff is used
instead. Note: if this job class also sets `limit: { concurrency: ... }` (see above), `count`
includes deliveries that were turned away for lack of a free slot, not just failed attempts.

## Error handlers

Error handlers receive every error Cosmo rescues — each failed job attempt, a failing stream batch, fetch and
scheduler errors, and rejected messages — so one hook reports them all:
```ruby
Cosmo.configure do |config|
  config.error_handlers << ->(error, context) { Honeybadger.notify(error, context: context) }
end
```
`context` is a Hash with a `:source` (`:job`, `:stream`, `:fetch`, `:scheduler`, `:reject`, `:retry_in`, `:limit`)
and what is known there: for a job its payload (`jid`, `class`, `args`, …), `stream`, `subject`, and `attempt`; for
a stream batch its `stream`, `processor`, and `size`. A handler that raises is logged and skipped.
