# =============================================================================
# CRAWL RUN MODEL
# =============================================================================
# A CrawlRun is one complete crawl session — one "press of the Run button."
# It tracks the search parameters, progress, and outcome.
#
# Status flow:  pending → running → completed
#                                 → failed
# =============================================================================

class CrawlRun < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  has_many :units,             dependent: :destroy  # All units found in this crawl
  has_many :crawl_log_entries, dependent: :destroy  # Detailed log entries for this crawl

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  validates :status, inclusion: {
    in:      %w[pending running completed failed],
    message: "Status must be one of: pending, running, completed, failed"
  }

  validates :search_radius_miles, numericality: {
    greater_than: 0,
    message:      "Radius must be greater than 0 miles"
  }, allow_nil: true

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  scope :completed,   -> { where(status: "completed") }
  scope :failed,      -> { where(status: "failed") }
  scope :running,     -> { where(status: "running") }
  scope :pending,     -> { where(status: "pending") }
  scope :recent,      -> { order(created_at: :desc) }
  scope :latest,      -> { order(completed_at: :desc).first }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------

  # Mark this crawl as started and save the start time
  def start!
    update!(status: "running", started_at: Time.current)
    log_info("Crawl started", company: "system")
  end

  # Mark this crawl as completed, calculate duration, save
  def complete!
    now = Time.current
    duration = started_at ? (now - started_at).round(1) : nil

    update!(
      status:           "completed",
      completed_at:     now,
      duration_seconds: duration
    )

    log_info(
      "Crawl completed in #{duration}s. " \
      "Found #{facilities_found} facilities, #{units_found} matching units.",
      company: "system"
    )
  end

  # Mark this crawl as failed with an error message
  def fail!(message)
    update!(
      status:        "failed",
      completed_at:  Time.current,
      error_message: message
    )

    log_error("Crawl FAILED: #{message}", company: "system")
  end

  # Increment the facilities_found counter (thread-safe)
  def increment_facilities!(count = 1)
    increment!(:facilities_found, count)
  end

  # Increment the units_found counter (thread-safe)
  def increment_units!(count = 1)
    increment!(:units_found, count)
  end

  # Increment the companies_crawled counter (thread-safe)
  def increment_companies_crawled!
    increment!(:companies_crawled)
  end

  # Increment the companies_failed counter (thread-safe)
  def increment_companies_failed!
    increment!(:companies_failed)
  end

  # Is this crawl currently in progress?
  def running?
    status == "running"
  end

  # Is this crawl done (either completed or failed)?
  def finished?
    %w[completed failed].include?(status)
  end

  # How long did the crawl take, as a human-readable string?
  # Example: "4 minutes and 32 seconds"
  def duration_label
    return "Not finished" unless duration_seconds
    return "Less than 1 second" if duration_seconds < 1

    minutes = (duration_seconds / 60).floor
    seconds = (duration_seconds % 60).round

    if minutes > 0
      "#{minutes} minute#{"s" if minutes != 1} and #{seconds} second#{"s" if seconds != 1}"
    else
      "#{seconds} second#{"s" if seconds != 1}"
    end
  end

  # Returns a summary string for display in the dashboard history table
  def summary
    case status
    when "completed"
      "#{facilities_found} facilities, #{units_found} units — #{duration_label}"
    when "failed"
      "FAILED: #{error_message&.truncate(100)}"
    when "running"
      "Running... #{companies_crawled} companies done so far"
    when "pending"
      "Waiting to start"
    end
  end

  # ---------------------------------------------------------------------------
  # LOGGING HELPERS
  # ---------------------------------------------------------------------------
  # These create CrawlLogEntry records AND write to the Rails log file.
  # Both places are logged so you can check either the database or crawl.log.
  # ---------------------------------------------------------------------------

  def log_info(message, company:, url: nil)
    write_log(level: "info", message: message, company: company, url: url)
  end

  def log_warning(message, company:, url: nil, retry_count: 0)
    write_log(level: "warning", message: message, company: company, url: url, retry_count: retry_count)
  end

  def log_error(message, company:, url: nil, retry_count: 0)
    write_log(level: "error", message: message, company: company, url: url, retry_count: retry_count)
  end

  def log_success(message, company:, url: nil)
    entry = write_log(level: "info", message: message, company: company, url: url)
    entry.update!(success: true)
    entry
  end

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------

  # Is any crawl currently running?
  def self.any_running?
    running.exists?
  end

  # Returns the most recently completed crawl run
  def self.latest_completed
    completed.order(completed_at: :desc).first
  end

  # Returns crawl runs from the last N months (for history display)
  def self.history(months: 6)
    where("created_at >= ?", months.months.ago).order(created_at: :desc)
  end

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  def write_log(level:, message:, company:, url: nil, retry_count: 0)
    # Write to database log entry
    entry = crawl_log_entries.create!(
      company:     company,
      url:         url,
      level:       level,
      message:     message,
      retry_count: retry_count
    )

    # Also write to Rails log file (goes to log/development.log or log/production.log)
    log_line = "[CrawlRun ##{id}][#{company}] #{message}"
    log_line += " URL: #{url}" if url
    log_line += " (retry #{retry_count})" if retry_count > 0

    case level
    when "error"   then Rails.logger.error(log_line)
    when "warning" then Rails.logger.warn(log_line)
    else                Rails.logger.info(log_line)
    end

    entry
  end
end
