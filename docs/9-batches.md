# Batches

Group jobs together and fire a callback once every one of them has finished. The registered class
is plain Ruby — it implements `on_complete(status, opts)` / `on_success(status, opts)`, not
`perform` — and runs on the job worker pool, not inline on whichever thread finalized the batch.
`status` is `{ bid:, total:, succeeded:, failed: }` and `opts` is whatever you passed to `#on`.

```ruby
batch = Cosmo::Batch.new
batch.jobs do
  ImportJob.perform_async(1)
  ImportJob.perform_async(2)
end
batch.on(:complete, NotifyUser, user_id: 1)  # fires once every job has finished, pass or fail
batch.on(:success, NotifyUser, user_id: 1)   # fires only if none of them failed

class NotifyUser
  def on_complete(status, opts)
    UserMailer.batch_done(opts[:user_id], status[:succeeded], status[:total]).deliver_later
  end

  def on_success(status, opts)
    UserMailer.batch_succeeded(opts[:user_id]).deliver_later
  end
end
```

- `#jobs` is the only place membership is tracked — jobs enqueued outside the block aren't part of
  the batch. Call it at least once (an empty block is fine) to close the batch.
- `:complete` always fires once every job is done. `:success` fires only if none were dead-lettered
  or dropped after exhausting retries. Both can be registered before or after `#jobs` — a callback
  registered after the batch has already finished still fires.

## Retried jobs: `jobs(retriable: true)`

`batch.jobs` keeps the batch open while its block runs, and lets the batch finish when the block ends. If the job
running the block is stopped halfway, for example by a deploy, and retried, that breaks: the batch finishes after the
jobs published so far and ignores the ones the retry publishes. Pass `retriable: true` in that case, and give the jobs
fixed ids so the retry doesn't enqueue the same job twice:

```ruby
class SliceJob
  include Cosmo::Job
  options retry: 3

  def perform(batch_id, rows)
    batch = Cosmo::Batch.new(bid: batch_id)
    batch.on(:complete, NotifyUser, user_id: 1)

    batch.jobs(retriable: true) do
      RowJob.set(jids: rows.map { "#{batch_id}-#{_1}" }).perform_bulk(rows.map { [_1] })
    end
  end
end
```

Say `SliceJob` has 6 rows, and it is stopped after publishing 3 of them. Then it is retried:

| | `jobs { }` | `jobs(retriable: true) { }` |
|---|---|---|
| First run, stopped halfway | the batch finishes once the 3 published jobs are done | the batch stays open |
| Retry | publishes rows 4-6, but the batch is already finished | skips rows 1-3, publishes rows 4-6 |
| `:complete` callback | fires once, early, with `total: 3` | fires once, after all 6 rows, with `total: 6` |
| Jobs 4-6 failing | not counted | counted in `failed` |

The block runs again on every retry, so only use `retriable: true` in jobs that are retried. A block that raises
without a retry leaves the batch open. Use it for one `jobs` call per batch.

## Nested batches

A running job can spawn its own sub-batch, which counts as one pending unit of its parent and propagates any failure
upward as a single failure unit:

```ruby
class ImportJob
  include Cosmo::Job

  def perform(account_id)
    sub_batch = Cosmo::Batch.new(parent: batch_id)  # batch_id is this job's own batch, if any
    sub_batch.jobs { SyncRecordJob.perform_async(account_id) }
  end
end
```

## Notes

- Batch tracking data (pending counts, callbacks, results) expires automatically after
  `config.batches.expiry` (default: 3 days), set in `Cosmo.configure`.
- Open and finished batches — with pending/succeeded/failed counts — are listed live on the web UI's **Batches** page.
- Only `Cosmo::Job`-based jobs are tracked; the ActiveJob adapter doesn't currently participate in
  batches (see [Active Job](15-active-job.md)).
