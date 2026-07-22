# =============================================================================
# APPLICATION JOB
# =============================================================================
# Base class for all background jobs.
# CrawlJob and AlertCheckerJob both inherit from this.
# =============================================================================

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs if they raise a transient exception
  # (e.g. a network timeout that might succeed on the next try)
  retry_on ActiveRecord::Deadlocked, attempts: 3, wait: :polynomially_longer
  retry_on ActiveJob::DeserializationError
end
