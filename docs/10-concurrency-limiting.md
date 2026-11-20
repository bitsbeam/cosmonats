# Concurrency limiting

```ruby
class ThirdPartyApiJob
  include Cosmo::Job
  # At most 3 instances of this job run at once, cluster-wide.
  # Jobs that lose the race are NAK'd and redelivered after half of `duration`,
  # or after `retry_in` when set (e.g. limit: { duration: 30, concurrency: 3, retry_in: 5 }).
  options limit: { duration: 30, concurrency: 3 }
end

class CrawlJob
  include Cosmo::Job
  # Durations take seconds or strings such as "82m", "2h" or "1h22m" (also for limit retry_in).
  options limit: { duration: "1h22m" }
end

class PerAccountSyncJob
  include Cosmo::Job
  # Scope the cap per key instead of class-wide — e.g. one concurrent sync per account.
  options limit: { duration: 30, concurrency: { to: 1, key: ->(account_id) { account_id } } }

  def perform(account_id)
    Account.find(account_id).sync!
  end
end
```
