# Sentry

```ruby
require "cosmo/middleware/sentry"

Cosmo.configure do |config|
  config.server_middleware { |c| c.add Cosmo::Middleware::Sentry }
  config.error_handlers << Cosmo::Middleware::Sentry::ERROR_HANDLER
end
```
The [middleware](13-middleware.md) wraps every job execution in a Sentry transaction (`queue.cosmonats`), and the
[error handler](12-error-handling.md#error-handlers) captures every error Cosmo rescues — failed jobs, stream batches, fetches, the
scheduler — with its context under `cosmonats`. No other setup beyond having `sentry-ruby` initialized.
