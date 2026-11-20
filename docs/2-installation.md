# Installation

```ruby
# Gemfile
gem "cosmonats"
```

**Requirements:** Ruby ≥ 3.2, NATS Server ≥ 2.14 with JetStream enabled ([install guide](https://docs.nats.io/running-a-nats-service/introduction/installation))

**Optional gems** — not installed with `cosmonats`, add them only for the features you use:

| Feature                                       | Gems              |
|-----------------------------------------------|-------------------|
| Monitoring UI (`Cosmo::Web`)                  | `rack`            |
| Health check HTTP server (`/health`, `/ping`) | `rack`, `webrick` |

```ruby
# Gemfile
gem "rack", "~> 3.0"
gem "webrick", "~> 1.9"
```

## NATS

Spin up NATS instantly with Docker — one command, that's it:
```bash
docker run -p 4222:4222 -p 8222:8222 nats:alpine -js
```

Or add it to your existing `docker-compose.yml`:
```yaml
services:
  nats:
    image: nats:alpine
    command: -js
    ports:
      - "4222:4222"
      - "8222:8222"
```

## Monitoring UI

Mount the monitoring UI in your Rack app:
```ruby
require "cosmo/web"

# Rails
mount Cosmo::Web => "/cosmo"

# Any Rack app (config.ru)
map "/cosmo" { run Cosmo::Web }
```

> [!WARNING]
> `Cosmo::Web` ships with **no authentication and no CSRF protection**, yet it exposes destructive actions
> (retrying and deleting jobs, pausing streams, running and deleting crons). Never expose it unprotected.

```ruby
# Rails, with Devise
authenticate :user, ->(user) { user.admin? } do
  mount Cosmo::Web => "/cosmo"
end

# Any Rack app (config.ru), with HTTP Basic auth
map "/cosmo" do
  use Rack::Auth::Basic, "Cosmo" do |user, password|
    Rack::Utils.secure_compare(user, ENV.fetch("COSMO_WEB_USER")) &
      Rack::Utils.secure_compare(password, ENV.fetch("COSMO_WEB_PASSWORD"))
  end
  run Cosmo::Web
end
```
