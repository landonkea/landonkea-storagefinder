# =============================================================================
# APPLICATION JOB
# =============================================================================
# Base class for all background jobs.
# CrawlJob and AlertCheckerJob both inherit from this.
# =============================================================================

# WHAT is a "job" here? Rails apps sometimes need to do slow work (like
# crawling websites or sending emails) WITHOUT making the user's web browser
# sit and wait for it to finish. "ActiveJob" is the part of Rails that lets
# you define a chunk of code as a background job, hand it off to be run
# later (possibly by a separate worker process), and immediately let the
# web request finish so the user's page loads fast.
#
# `class ApplicationJob < ActiveJob::Base` defines a new Ruby class named
# ApplicationJob. The `< ActiveJob::Base` part means "inherits from
# ActiveJob::Base", this class automatically gets all of ActiveJob's
# built-in behavior (being queueable, retryable, serializable, etc.)
# without us having to write that plumbing ourselves.
#
# This particular class is intentionally almost empty. Rails convention is
# to generate one shared "ApplicationJob" that every other job in the app
# inherits from (just like ApplicationController is the shared base for
# controllers, and ApplicationRecord is the shared base for models). Putting
# shared settings here (like the retry rules below) means EVERY job in the
# app gets them automatically, instead of having to repeat them in each job
# file individually.
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs if they raise a transient exception
  # (e.g. a network timeout that might succeed on the next try)
  #
  # `retry_on` is an ActiveJob class method (a method you call directly on
  # the class, not on an instance of it) that configures automatic retry
  # behavior: if a job's `perform` method raises the given exception class,
  # ActiveJob will catch it and re-run the job instead of letting it die.
  #
  # ActiveRecord::Deadlocked is the error Rails raises when two database
  # operations block each other (a "deadlock"), this is usually a
  # temporary timing issue, so simply trying again is a reasonable fix.
  # `attempts: 3` means it will try up to 3 times total before giving up.
  # `wait: :polynomially_longer` means each retry waits longer than the
  # last (instead of retrying instantly, which could hit the same deadlock
  # again immediately), this is a built-in ActiveJob backoff strategy.
  retry_on ActiveRecord::Deadlocked, attempts: 3, wait: :polynomially_longer

  # ActiveJob::DeserializationError happens when a job was queued with a
  # reference to a database record (like "the CrawlRun with id 5") but by
  # the time a worker picks the job up to run it, that record has since
  # been deleted, so ActiveJob can't "deserialize" (rebuild) the argument
  # from the database anymore. Retrying here uses ActiveJob's default retry
  # settings (no `attempts:`/`wait:` given), on the chance the record
  # reappears or the underlying issue was transient.
  retry_on ActiveJob::DeserializationError
end
# `end` closes the `class ApplicationJob` definition that started above,
# nothing after this point is part of the class.
