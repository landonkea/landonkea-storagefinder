# =============================================================================
# CRAWL LOG ENTRY MODEL
# =============================================================================
# One row per log message within a crawl run.
# These power the live log feed on the dashboard and the downloadable crawl.log
# =============================================================================

# `class CrawlLogEntry < ApplicationRecord` defines a Ruby class named
# CrawlLogEntry that inherits from ApplicationRecord (see
# app/models/application_record.rb). Inheriting from ApplicationRecord (an
# "ActiveRecord model") means each instance of this class represents one row
# in the "crawl_log_entries" database table, and each column on that table
# (company, message, level, url, retry_count, created_at, ...) becomes an
# attribute you can read/write like a normal Ruby method, e.g. `entry.message`.
class CrawlLogEntry < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  # `belongs_to` declares a relationship to another model: this table has a
  # foreign key column (here, `crawl_run_id`) pointing at one row in another
  # table. `belongs_to :crawl_run` tells Rails that every CrawlLogEntry
  # belongs to exactly one CrawlRun record, and generates an `entry.crawl_run`
  # method that looks up and returns that related CrawlRun.
  belongs_to :crawl_run

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # `validates` declares a rule a record must satisfy before Rails will save
  # it to the database. If the rule fails, Rails blocks the save and attaches
  # a human-readable error message (visible via `record.errors`) instead.

  # Requires `company` to be present (not nil, not an empty string).
  validates :company, presence: { message: "Company is required on a log entry" }
  # Requires `message` to be present too — a log entry with no text is
  # useless, so this prevents accidentally saving a blank one.
  validates :message, presence: { message: "Log message cannot be blank" }
  # Requires `level` to be one of exactly these three strings. `%w[info
  # warning error]` is Ruby shorthand for the array
  # `["info", "warning", "error"]` — each space-separated word becomes its
  # own array element automatically, no quotes/commas needed.
  validates :level,   inclusion: {
    in:      %w[info warning error],
    message: "Log level must be 'info', 'warning', or 'error'"
  }

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  # A "scope" is a named, reusable database query exposed as a class method,
  # e.g. `CrawlLogEntry.errors`. Each is defined with a lambda (`-> { ... }`)
  # wrapping a `where`/`order` call that Rails turns into a chainable query.

  # Returns only log entries whose level is "error".
  scope :errors,   -> { where(level: "error") }
  # Returns only log entries whose level is "warning".
  scope :warnings, -> { where(level: "warning") }
  # Returns only log entries whose level is "info".
  scope :infos,    -> { where(level: "info") }
  # Returns all log entries ordered newest-first (`created_at` descending).
  scope :recent,   -> { order(created_at: :desc) }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------
  # Everything below is a regular Ruby method callable on one particular
  # CrawlLogEntry record, e.g. `some_entry.to_log_line`.

  # Returns a formatted string suitable for writing to a log file
  # Example: "[2024-01-15 14:32:01] [INFO] [Extra Space Storage] Successfully found 12 units at URL: https://..."
  def to_log_line
    # `.strftime(...)` formats a Time/DateTime value into a string using a
    # pattern of format codes: %Y = 4-digit year, %m = 2-digit month,
    # %d = 2-digit day, %H = hour (24h), %M = minute, %S = second.
    timestamp = created_at.strftime("%Y-%m-%d %H:%M:%S")
    # Builds an array of the fixed pieces of the log line. `"[#{timestamp}]"`
    # uses Ruby string interpolation — the `#{ }` part is evaluated as Ruby
    # code and its result is spliced into the surrounding string.
    # `level.upcase` converts the level string ("info") to uppercase ("INFO").
    parts = [ "[#{timestamp}]", "[#{level.upcase}]", "[#{company}]", message ]
    # `parts << "..."` appends (using the `<<` "shovel" operator) an extra
    # piece onto the end of the array, but only when the condition after
    # `if` is true. `.present?` is a Rails helper meaning "not nil and not
    # blank" — so a URL segment is only added if this entry actually has one.
    parts << "URL: #{url}" if url.present?
    # `retry_count.to_i` converts retry_count to an integer (safely handling
    # nil, which becomes 0) so it can be compared with `> 0`. Only append
    # the "(retry N)" note if this entry actually represents a retry.
    parts << "(retry #{retry_count})" if retry_count.to_i > 0
    # `.join(" ")` combines every element of `parts` into one string,
    # separated by single spaces — this is the method's return value since
    # it's the last expression evaluated (Ruby methods return their last
    # evaluated expression without needing an explicit `return`).
    parts.join(" ")
  end
  # `end` closes the `def to_log_line` method definition.

  # Returns a CSS class for coloring the log line in the dashboard feed
  def css_class
    # `case level ... when ... then ... end` is Ruby's multi-branch
    # conditional. It compares `level` against each `when` value in turn and
    # returns the value after `then` for the first match. `then` here is
    # just a way to put the branch's result on the same line as `when`,
    # rather than on the next line.
    case level
    when "error"   then "log-error"    # Red
    when "warning" then "log-warning"  # Yellow
    else                "log-info"     # Gray/white
    end
    # `end` closes the `case level` block above; its result (whichever
    # string matched) is this method's return value.
  end
  # `end` closes the `def css_class` method definition.

  # Returns an emoji prefix for the log line (used in Discord messages)
  def emoji_prefix
    # Same `case`/`when`/`else` pattern as css_class above, but returning an
    # emoji character instead of a CSS class name for use in Discord alerts.
    case level
    when "error"   then "🔴"
    when "warning" then "🟡"
    else                "🟢"
    end
    # `end` closes the `case level` block above.
  end
  # `end` closes the `def emoji_prefix` method definition.
end
# `end` closes the `class CrawlLogEntry < ApplicationRecord` block that
# started at the top of the file.
