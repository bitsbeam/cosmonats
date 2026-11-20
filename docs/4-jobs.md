# Jobs

```ruby
class ReportJob
  include Cosmo::Job

  options(
    stream: :critical,  # Stream name
    retry: 5,           # Retry attempts
    dead: true          # Send to dead letter queue on final failure
  )

  def perform(report_id)
    logger.info "Processing report #{report_id}"
    Report.find(report_id).generate!
  rescue StandardError => e
    logger.error "Failed: #{e.message}"
    raise  # Triggers retry with exponential backoff
  end
end

ReportJob.perform_async(42)                              # Enqueue now
ReportJob.perform_in(30.minutes, 42)                     # Delayed
ReportJob.perform_at(Time.parse("2026-01-25 10:00"), 42) # Scheduled
ReportJob.perform_sync(42)                               # Inline, no NATS (great for tests)
ReportJob.set(stream: :critical, retry: 0).perform_async(42) # Per-call stream, retry, dead or subject
ReportJob.perform_bulk([[1], [2], [3]])                  # One job per argument list, see below
```

`perform_bulk` publishes a thousand jobs at a time without waiting on each ack, which is many times faster than
calling `perform_async` in a loop. It takes the same options (`perform_bulk(list, in: 60)`, `set(...).perform_bulk`),
joins the current batch, and returns the jids in order. When the stream refuses some jobs, e.g. a full `discard: new`
stream, it raises `Cosmo::BulkEnqueueError`: its `jids` are `nil` for the jobs that weren't enqueued, `errors` says why
by index, and the chunks after the failing one aren't published. Inside a [batch](9-batches.md), the refused jobs never
join it, so rescue within `jobs` to resend them while the batch is still open:
```ruby
batch.jobs do
  list = ids.zip
  ReportJob.perform_bulk(list)
rescue Cosmo::BulkEnqueueError => e
  ReportJob.perform_bulk(list.reject.with_index { |_, i| e.jids[i] })
end
```
An error that is a `NATS::Timeout` means no ack came back, not that the job wasn't stored, so resending it can run that
job twice.

Inside `perform`, the job instance knows about the message it came from:

| Accessor       | Value                                                                                   |
|----------------|-----------------------------------------------------------------------------------------|
| `jid`          | Job id, returned by `perform_async`                                                     |
| `attempt`      | 1-based delivery attempt                                                                |
| `enqueued_at`  | `Time` the job was enqueued; for a cron job, when NATS fired the schedule               |
| `scheduled_by` | Subject of the cron schedule that fired the job, `nil` for jobs enqueued any other way  |
| `batch_id`     | Id of the [batch](9-batches.md) the job belongs to, `nil` outside a batch                   |
