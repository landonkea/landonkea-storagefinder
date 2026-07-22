# =============================================================================
# CRAWL LOG ENTRY MODEL
# =============================================================================
# One row per log message within a crawl run.
# These power the live log feed on the dashboard and the downloadable crawl.log
# =============================================================================

class CrawlLogEntry < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  belongs_to :crawl_run

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  validates :company, presence: { message: "Company is required on a log entry" }
  validates :message, presence: { message: "Log message cannot be blank" }
  validates :level,   inclusion: {
    in:      %w[info warning error],
    message: "Log level must be 'info', 'warning', or 'error'"
  }

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  scope :errors,   -> { where(level: "error") }
  scope :warnings, -> { where(level: "warning") }
  scope :infos,    -> { where(level: "info") }
  scope :recent,   -> { order(created_at: :desc) }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------

  # Returns a formatted string suitable for writing to a log file
  # Example: "[2024-01-15 14:32:01] [INFO] [Extra Space Storage] Successfully found 12 units at URL: https://..."
  def to_log_line
    timestamp = created_at.strftime("%Y-%m-%d %H:%M:%S")
    parts = [ "[#{timestamp}]", "[#{level.upcase}]", "[#{company}]", message ]
    parts << "URL: #{url}" if url.present?
    parts << "(retry #{retry_count})" if retry_count.to_i > 0
    parts.join(" ")
  end

  # Returns a CSS class for coloring the log line in the dashboard feed
  def css_class
    case level
    when "error"   then "log-error"    # Red
    when "warning" then "log-warning"  # Yellow
    else                "log-info"     # Gray/white
    end
  end

  # Returns an emoji prefix for the log line (used in Discord messages)
  def emoji_prefix
    case level
    when "error"   then "🔴"
    when "warning" then "🟡"
    else                "🟢"
    end
  end
end
