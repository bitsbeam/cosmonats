# Cron

Recurring jobs, without a separate scheduler process. A schedule is just a message parked in the
`scheduled` stream (requires NATS Server 2.14+) — NATS fires it on the cron expression, and the
worker's scheduler dispatches the job on to the stream that runs it, the same path a delayed job
takes. Deploy it once; whatever's in NATS is exactly what runs and exactly what shows up in the web
UI's **Crons** tab, where each entry can be inspected, run immediately, or deleted.

Every schedule lives in `scheduled` because NATS only lets a schedule fire at a subject its own
stream covers, and refuses `discard: new` on any stream with scheduling enabled. Keeping schedules
in one stream leaves every stream that actually runs jobs free to choose its own discard policy.
The trade is that cron firings are dispatched by the scheduler, so at least one worker has to be
running without `--no-scheduler`.

Declare schedules right in `config/cosmo.yml`:

```yaml
setup:
  cron:
    daily_report:
      class: ReportJob
      schedule: "@daily"        # @-shortcuts are passed straight through to NATS
      stream: default
    weekday_digest:
      class: ReportJob
      schedule: "0 9 * * 1-5"   # 6-field NATS cron (seconds first); 5-field UNIX cron is auto-normalized
      stream: default
      args: ["daily"]
      timezone: America/New_York # optional, cron expressions only
```

Like `consumers.jobs`, `setup.cron` can be a list of groups (`- daily_report: {...}`) to keep related schedules together.
They are flattened on load, so a name may appear in one group only.

`cosmo -C config/cosmo.yml -S` syncs it — whatever's in the file is exactly what ends up scheduled in NATS, same as streams.

Prefer to manage schedules at runtime instead? The same operations are available from Ruby:

```ruby
Cosmo::API::Cron.instance.upsert!(
  class_name: "ReportJob", stream: "default", schedule: "0 9 * * 1-5",
  args: ["daily"], timezone: "America/New_York", name: "weekday_report"
)

Cosmo::API::Cron.instance.all                                    # every schedule currently deployed
Cosmo::API::Cron.instance.run_now!("cosmo.cron.default.report_job.weekday_report")  # bypass the timer
Cosmo::API::Cron.instance.delete!("cosmo.cron.default.report_job.weekday_report")   # stop future firings
```
