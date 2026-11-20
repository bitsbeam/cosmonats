# Upgrading

## 0.7 → 0.8

0.8 renames Cosmo's internal NATS storage and changes the `dead` stream's retention. Nothing is migrated
automatically; these steps carry an existing deployment over. Run the `nats` commands against your production
context.

**Before deploying**

- Remove `scheduled` and `dead` from `setup.jobs` and `consumers.jobs` in `config/cosmo.yml`, and `batch_expiry`
  (now `config.batches.expiry` in `Cosmo.configure`). Cosmo creates and tunes those streams itself.
- Replace `require "cosmo/sentry/auto"` with:
  ```ruby
  require "cosmo/middleware/sentry"

  Cosmo.configure do |config|
    config.server_middleware { |chain| chain.add Cosmo::Middleware::Sentry }
    config.error_handlers << Cosmo::Middleware::Sentry::ERROR_HANDLER
  end
  ```
- Replace any `Cosmo::Config.set(...)` with `cosmo.yml` entries or `Cosmo.configure`.
- Deploy while no batch is open and no concurrency-limited job is running: batch state and limit slots move to new
  buckets, which old and new workers don't share during a rolling deploy.

**1. Deploy every worker and web process.** No old process may keep running, or it keeps counting into the old
streams.

**2. Recreate the `dead` stream** (it switches to `workqueue` retention, which NATS can't change in place):
```bash
nats stream backup dead ./dead-backup   # optional: keep the parked jobs
nats stream rm dead -f
```

**3. Create the new streams:**
```bash
bundle exec cosmo -C config/cosmo.yml --setup
```

**4. Copy the lifetime totals** from `_cosmostats` (the `{"val":"N"}` of each message) into `_cosmototals`:
```bash
nats stream get _cosmostats --last-for _cosmostats.jobs.processed
nats stream get _cosmostats --last-for _cosmostats.jobs.failed

nats pub _cosmototals.jobs.processed "" -H "Nats-Incr:+<processed>" --jetstream
nats pub _cosmototals.jobs.failed    "" -H "Nats-Incr:+<failed>"    --jetstream
```
The values are added, so jobs counted since the deploy are kept.

**5. Delete the old stream and buckets** — whichever of these exist (`nats stream ls --names`; a bucket shows up as
`KV_<bucket>`):
```bash
nats stream rm _cosmostats -f
nats kv del cosmo_jobs_batches -f
nats kv del cosmo_jobs_busy -f
nats kv del cosmo_processes -f
nats kv del cosmo_jobs_limits -f
nats kv del cosmostats -f         # left by early versions
```

Afterwards Cosmo's own storage is `_cosmototals`, `_cosmobatches`, `_cosmometrics`, `scheduled`, `dead`, and the
`KV__cosmo…` buckets; the limits and batches buckets appear when first used.
