# =============================================================================
# CRAWL RUN MODEL
# =============================================================================
# A CrawlRun is one complete crawl session — one "press of the Run button."
# It tracks the search parameters, progress, and outcome.
#
# Status flow:  pending → running → completed
#                                 → failed
# =============================================================================

# `class CrawlRun < ApplicationRecord` defines a Ruby class named CrawlRun
# that inherits from ApplicationRecord (see app/models/application_record.rb).
# Inheriting from ApplicationRecord makes this an "ActiveRecord model": each
# instance of CrawlRun represents one row of the "crawl_runs" database table,
# and every column on that table (status, started_at, facilities_found, ...)
# is automatically readable/writable like a plain Ruby attribute.
class CrawlRun < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  # `has_many` declares that one CrawlRun record can be related to MANY rows
  # in another table (the reverse side of that other table's `belongs_to`).
  # It generates a method like `crawl_run.units` that queries and returns
  # every Unit whose `crawl_run_id` column points at this record.
  has_many :units,             dependent: :destroy  # All units found in this crawl
  has_many :crawl_log_entries, dependent: :destroy  # Detailed log entries for this crawl
  # `dependent: :destroy` tells Rails: when a CrawlRun record is deleted,
  # automatically delete every associated Unit/CrawlLogEntry too — this
  # prevents leaving "orphaned" rows in those tables that point at a
  # crawl_run_id which no longer exists.

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # `validates` declares a rule a record must satisfy before Rails will save
  # it. If it fails, Rails blocks the save and attaches a readable error
  # message (accessible via `record.errors`) instead of writing to the DB.

  # Requires `status` to be one of exactly these four strings. `%w[...]` is
  # Ruby shorthand for an array of strings — each space-separated word
  # becomes its own element, equivalent to
  # `["pending", "running", "completed", "failed"]`.
  validates :status, inclusion: {
    in:      %w[pending running completed failed],
    message: "Status must be one of: pending, running, completed, failed"
  }

  # Requires search_radius_miles, when present, to be a number greater than
  # zero. `allow_nil: true` means this rule is skipped entirely if the value
  # is nil (so nil radii aren't forced to have a value here).
  validates :search_radius_miles, numericality: {
    greater_than: 0,
    message:      "Radius must be greater than 0 miles"
  }, allow_nil: true

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  # A "scope" is a named, reusable database query exposed as a class method,
  # e.g. `CrawlRun.completed`. Each one below is a lambda (`-> { ... }`)
  # wrapping a query that Rails turns into a chainable class method.

  # Returns only crawl runs whose status is "completed".
  scope :completed,   -> { where(status: "completed") }
  # Returns only crawl runs whose status is "failed".
  scope :failed,      -> { where(status: "failed") }
  # Returns only crawl runs whose status is "running".
  scope :running,     -> { where(status: "running") }
  # Returns only crawl runs whose status is "pending".
  scope :pending,     -> { where(status: "pending") }
  # Returns all crawl runs, newest-created first.
  scope :recent,      -> { order(created_at: :desc) }
  # Returns the single most-recently-completed crawl run (by completed_at).
  # Note this scope calls `.first` itself, so unlike the other scopes above
  # it returns ONE record (or nil), not a chainable query of many records.
  scope :latest,      -> { order(completed_at: :desc).first }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------
  # Everything below (until the CLASS METHODS section) is a regular Ruby
  # method callable on one particular CrawlRun record, e.g. `some_run.start!`.

  # Mark this crawl as started and save the start time
  #
  # The trailing `!` in method names like `start!`, `complete!`, `fail!` is a
  # Ruby naming convention (not special syntax) meaning "this method has an
  # important side effect / can raise an error," as a signal to readers —
  # here, each one writes to the database and can raise if validation fails.
  def start!
    # `update!` is a Rails method that sets the given attributes AND saves
    # the record in one step, running validations. The `!` version raises
    # an exception (`ActiveRecord::RecordInvalid`) if validation fails,
    # instead of silently returning false like the non-bang `update` would.
    # `Time.current` returns the current time in the app's configured time
    # zone (preferred in Rails over plain `Time.now`).
    update!(status: "running", started_at: Time.current)
    # Calls the log_info instance method (defined further down this file)
    # to record a log entry noting the crawl started. `company: "system"`
    # is a keyword argument — log entries normally attach to one scraped
    # company, so "system" marks this as an internal/administrative entry.
    log_info("Crawl started", company: "system")
  end
  # `end` closes the `def start!` method definition.

  # Mark this crawl as completed, calculate duration, save
  def complete!
    # `now` stores the current time so it's captured once and reused below
    # (rather than calling Time.current twice, which could get two
    # very-slightly-different timestamps).
    now = Time.current
    # `started_at ? (now - started_at).round(1) : nil` is Ruby's ternary
    # conditional operator: `condition ? value_if_true : value_if_false`.
    # If `started_at` is present (truthy), compute the elapsed seconds by
    # subtracting two Time values (which yields a number of seconds) and
    # round to 1 decimal place; otherwise duration is nil (e.g. if start!
    # was never called for some reason).
    duration = started_at ? (now - started_at).round(1) : nil

    # Updates three columns at once and saves. Passing a hash literal
    # across multiple lines (each `key: value,` pair) is just a readability
    # style choice — Ruby doesn't require the line breaks or trailing commas
    # to be aligned like this, but it's common for multi-argument calls.
    update!(
      status:           "completed",
      completed_at:     now,
      duration_seconds: duration
    )

    # Records a log entry summarizing the completed crawl. The `\` at the
    # end of the first string line is Ruby's line-continuation syntax for
    # string literals: it tells Ruby "this string continues on the next
    # line" so the two lines are concatenated into one string with no
    # newline inserted between them.
    log_info(
      "Crawl completed in #{duration}s. " \
      "Found #{facilities_found} facilities, #{units_found} matching units.",
      company: "system"
    )
  end
  # `end` closes the `def complete!` method definition.

  # Mark this crawl as failed with an error message
  # `def fail!(message)` — `message` is a required positional argument: the
  # error text describing why the crawl failed.
  def fail!(message)
    update!(
      status:        "failed",
      completed_at:  Time.current,
      error_message: message
    )

    # Records this as an ERROR-level log entry (see log_error below) rather
    # than an info-level one, since the crawl actually failed.
    log_error("Crawl FAILED: #{message}", company: "system")
  end
  # `end` closes the `def fail!` method definition.

  # Increment the facilities_found counter (thread-safe)
  # `count = 1` gives `count` a default value of 1 when the caller omits
  # this (positional, not keyword) argument, e.g. `run.increment_facilities!`
  # with no argument still works and adds 1.
  def increment_facilities!(count = 1)
    # `increment!` is a built-in Rails method that atomically adds `count`
    # to the given numeric column and immediately saves — "atomically"
    # means the database itself performs the addition in one operation,
    # avoiding race conditions where two simultaneous crawls could both
    # read the same old value and overwrite each other's increments.
    increment!(:facilities_found, count)
  end
  # `end` closes the `def increment_facilities!` method definition.

  # Increment the units_found counter (thread-safe)
  def increment_units!(count = 1)
    increment!(:units_found, count)
  end
  # `end` closes the `def increment_units!` method definition.

  # Increment the companies_crawled counter (thread-safe)
  # No `count` argument here — `increment!` defaults to adding 1 when no
  # amount is given as its second argument.
  def increment_companies_crawled!
    increment!(:companies_crawled)
  end
  # `end` closes the `def increment_companies_crawled!` method definition.

  # Increment the companies_failed counter (thread-safe)
  def increment_companies_failed!
    increment!(:companies_failed)
  end
  # `end` closes the `def increment_companies_failed!` method definition.

  # Is this crawl currently in progress?
  # The trailing `?` on `running?` is a naming convention (not special
  # syntax) signaling this method returns true/false. Its body is a single
  # comparison, which is also its return value (Ruby methods return the
  # last expression evaluated, no explicit `return` needed).
  def running?
    status == "running"
  end
  # `end` closes the `def running?` method definition.

  # Is this crawl done (either completed or failed)?
  def finished?
    # `%w[completed failed]` builds the array `["completed", "failed"]`.
    # `.include?(status)` checks whether that array contains the current
    # value of `status`, returning true/false.
    %w[completed failed].include?(status)
  end
  # `end` closes the `def finished?` method definition.

  # How long did the crawl take, as a human-readable string?
  # Example: "4 minutes and 32 seconds"
  def duration_label
    # `return "..." unless duration_seconds` is the inline modifier form of
    # `unless` (opposite of `if`) — it returns early with this string only
    # when duration_seconds is nil/false (i.e. the crawl never finished).
    return "Not finished" unless duration_seconds
    # Similarly, returns early with a friendlier label for sub-1-second
    # crawls instead of printing "0 seconds".
    return "Less than 1 second" if duration_seconds < 1

    # `(duration_seconds / 60).floor` divides total seconds by 60 to get
    # minutes, then `.floor` rounds DOWN to the nearest whole number
    # (dropping any fractional minute) — e.g. 272 seconds / 60 = 4.53,
    # floored to 4 minutes.
    minutes = (duration_seconds / 60).floor
    # `duration_seconds % 60` is the modulo operator — the REMAINDER after
    # dividing by 60, i.e. "how many seconds are left over after removing
    # whole minutes." `.round` rounds that remainder to the nearest whole
    # second for display.
    seconds = (duration_seconds % 60).round

    if minutes > 0
      # Builds a string like "4 minutes and 32 seconds". The
      # `#{"s" if minutes != 1}` piece is string interpolation containing a
      # conditional expression: if minutes isn't exactly 1, it evaluates to
      # the string "s" (pluralizing "minute" -> "minutes"); if minutes IS 1,
      # the `if` condition is false and the expression evaluates to nil,
      # which interpolates as an empty string — giving "1 minute" (no "s").
      # The same pattern is repeated for "second"/"seconds".
      "#{minutes} minute#{"s" if minutes != 1} and #{seconds} second#{"s" if seconds != 1}"
    else
      # No whole minutes elapsed — just show the seconds, still pluralized
      # correctly using the same technique as above.
      "#{seconds} second#{"s" if seconds != 1}"
    end
    # `end` closes the `if minutes > 0 ... else ... end` block above; its
    # result is this method's return value.
  end
  # `end` closes the `def duration_label` method definition.

  # Returns a summary string for display in the dashboard history table
  def summary
    case status
    when "completed"
      "#{facilities_found} facilities, #{units_found} units — #{duration_label}"
    when "failed"
      # `error_message&.truncate(100)` uses Ruby's "safe navigation"
      # operator `&.` — it calls `.truncate(100)` only if error_message is
      # NOT nil; if error_message IS nil, the whole expression short-
      # circuits to nil instead of raising a NoMethodError. `.truncate(100)`
      # is a Rails String helper that shortens the string to at most 100
      # characters, adding "..." at the end if it had to cut anything.
      "FAILED: #{error_message&.truncate(100)}"
    when "running"
      "Running... #{companies_crawled} companies done so far"
    when "pending"
      "Waiting to start"
    end
    # `end` closes the `case status` block above. Note there is no `else`
    # branch here — if `status` somehow held a value outside the four
    # allowed by this model's inclusion validation, this method would
    # return nil (Ruby's `case` returns nil when nothing matches and there
    # is no `else`).
  end
  # `end` closes the `def summary` method definition.

  # ---------------------------------------------------------------------------
  # LOGGING HELPERS
  # ---------------------------------------------------------------------------
  # These create CrawlLogEntry records AND write to the Rails log file.
  # Both places are logged so you can check either the database or crawl.log.
  # ---------------------------------------------------------------------------

  # `company:` (required keyword argument, no default) and `url: nil`
  # (optional keyword argument, defaults to nil) — keyword arguments must be
  # called by name, e.g. `log_info("text", company: "Acme")`, which makes
  # call sites self-documenting compared to plain positional arguments.
  def log_info(message, company:, url: nil)
    # Delegates to the private write_log method (defined near the bottom of
    # this file) with level fixed to "info".
    write_log(level: "info", message: message, company: company, url: url)
  end
  # `end` closes the `def log_info` method definition.

  def log_warning(message, company:, url: nil, retry_count: 0)
    write_log(level: "warning", message: message, company: company, url: url, retry_count: retry_count)
  end
  # `end` closes the `def log_warning` method definition.

  def log_error(message, company:, url: nil, retry_count: 0)
    write_log(level: "error", message: message, company: company, url: url, retry_count: retry_count)
  end
  # `end` closes the `def log_error` method definition.

  def log_success(message, company:, url: nil)
    # Creates an info-level log entry first, capturing the created
    # CrawlLogEntry record in the local variable `entry` (write_log returns
    # the record it created — see the bottom of this file).
    entry = write_log(level: "info", message: message, company: company, url: url)
    # Then marks that specific entry's `success` column as true — a second,
    # separate database write after the first `create!` inside write_log.
    entry.update!(success: true)
    # Returns the (now-updated) entry to the caller — the last expression
    # evaluated in the method is its return value.
    entry
  end
  # `end` closes the `def log_success` method definition.

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------
  # `def self.method_name` (as opposed to plain `def method_name`) defines a
  # CLASS method — called on the class itself, e.g. `CrawlRun.any_running?`,
  # rather than on one particular record like `some_run.running?`. This is
  # the standard Ruby way to define "static"/class-level methods.

  # Is any crawl currently running?
  def self.any_running?
    # `running` here calls the `running` SCOPE defined earlier in this file
    # (not the `running?` instance method — different names, `running` vs
    # `running?`), which returns a query for all CrawlRun rows with
    # status "running". `.exists?` runs an efficient SQL check for whether
    # that query would return any rows at all, without loading them.
    running.exists?
  end
  # `end` closes the `def self.any_running?` class method definition.

  # Returns the most recently completed crawl run
  def self.latest_completed
    # `completed` calls the `completed` scope (status == "completed"),
    # then `.order(completed_at: :desc)` sorts those results newest-first,
    # then `.first` takes just the single most-recent record (or nil if
    # there are none).
    completed.order(completed_at: :desc).first
  end
  # `end` closes the `def self.latest_completed` class method definition.

  # Returns crawl runs from the last N months (for history display)
  # `months: 6` is a keyword argument with a default of 6, so callers can
  # write `CrawlRun.history` (defaults to 6 months) or
  # `CrawlRun.history(months: 12)` to override it.
  def self.history(months: 6)
    # `months.months.ago` mirrors the `n.days.ago` pattern seen in
    # ApplicationRecord: `.months` converts the plain integer into a
    # duration of that many months, and `.ago` subtracts it from the
    # current time. `where("created_at >= ?", ...)` uses a `?` placeholder
    # so the value is safely substituted into the SQL (avoiding SQL
    # injection), rather than directly interpolating it into the string.
    where("created_at >= ?", months.months.ago).order(created_at: :desc)
  end
  # `end` closes the `def self.history` class method definition.

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  # `private` marks everything below it as callable only from inside this
  # class (e.g. by the log_info/log_warning/log_error/log_success methods
  # above), not from outside code like controllers.
  private

  # The shared implementation behind log_info/log_warning/log_error: builds
  # and saves one CrawlLogEntry, and also writes a matching line to the
  # Rails application log file. `level:`, `message:`, `company:` are
  # required keyword arguments; `url:` and `retry_count:` are optional with
  # defaults.
  def write_log(level:, message:, company:, url: nil, retry_count: 0)
    # Write to database log entry
    # `crawl_log_entries` here calls the `has_many :crawl_log_entries`
    # association defined near the top of this file — calling `.create!`
    # on it builds a new CrawlLogEntry that is automatically linked to THIS
    # CrawlRun (its crawl_run_id is set for you), saves it, and raises if
    # validation fails (the `!` variant, same convention as update!).
    entry = crawl_log_entries.create!(
      company:     company,
      url:         url,
      level:       level,
      message:     message,
      retry_count: retry_count
    )

    # Also write to Rails log file (goes to log/development.log or log/production.log)
    # Builds a plain string for the Rails logger, separate from the
    # database record above. `id` here refers to this CrawlRun's own
    # primary key (its database row ID).
    log_line = "[CrawlRun ##{id}][#{company}] #{message}"
    # `+=` appends to and reassigns `log_line` (shorthand for
    # `log_line = log_line + "..."`) — only runs when `url` is present
    # (truthy; note this doesn't use `.present?` here, just Ruby's plain
    # truthiness where anything except `nil`/`false` counts as true).
    log_line += " URL: #{url}" if url
    log_line += " (retry #{retry_count})" if retry_count > 0

    # Chooses which Rails.logger method to call based on the log level —
    # Rails.logger writes to the environment's log file (e.g.
    # log/development.log) at the given severity, which affects how it's
    # filtered/displayed by log-viewing tools.
    case level
    when "error"   then Rails.logger.error(log_line)
    when "warning" then Rails.logger.warn(log_line)
    else                Rails.logger.info(log_line)
    end
    # `end` closes the `case level` block above.

    # Returns the created CrawlLogEntry record to the caller (used by
    # log_success above to then call `.update!(success: true)` on it).
    entry
  end
  # `end` closes the `def write_log` method definition.
end
# `end` closes the `class CrawlRun < ApplicationRecord` block that started
# at the top of the file.
