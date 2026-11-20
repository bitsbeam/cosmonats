# Quick start

## 1. Configure (optional)

Nothing is required: without `config/cosmo.yml`, Cosmo runs one `default` job stream plus its own service streams.
To change anything, write Cosmo's defaults into your project and edit them:

```bash
bundle exec cosmo --init # writes config/cosmo.yml
```

## 2. Create streams in NATS (one-time, idempotent)

```bash
bundle exec cosmo -S
```

## 3. Define a job in `app/jobs/`

```ruby
class SendEmailJob
  include Cosmo::Job
  options stream: :default, retry: 3, dead: true

  def perform(user_id, email_type)
    UserMailer.send(email_type, user_id).deliver_now
  end
end
```

## 4. Enqueue & run

```ruby
SendEmailJob.perform_async(42, "welcome")
```

```bash
bundle exec cosmo -C config/cosmo.yml -c 10 -r ./app/jobs jobs
```
