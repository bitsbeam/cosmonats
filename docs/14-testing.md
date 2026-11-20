# Testing

```ruby
# Synchronous — no NATS needed
SendEmailJob.perform_sync(123, "test")

# Async — returns a job ID
jid = SendEmailJob.perform_async(123, "welcome")
assert_kind_of String, jid
```
