# frozen_string_literal: true

require "cosmo/job/processor"
require "cosmo/sentry/job_processor_middleware"

Cosmo::Job::Processor.prepend Cosmo::Sentry::JobProcessorMiddleware
