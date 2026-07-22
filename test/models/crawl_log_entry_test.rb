require "test_helper"

class CrawlLogEntryTest < ActiveSupport::TestCase
  def valid_attributes
    { crawl_run: crawl_runs(:current_completed), company: "Test Co", message: "hello", level: "info" }
  end

  test "requires company and message" do
    entry = CrawlLogEntry.new(valid_attributes.merge(company: "", message: ""))
    refute entry.valid?
    assert_includes entry.errors[:company], "Company is required on a log entry"
    assert_includes entry.errors[:message], "Log message cannot be blank"
  end

  test "level must be info, warning, or error" do
    entry = CrawlLogEntry.new(valid_attributes.merge(level: "critical"))
    refute entry.valid?
    assert_includes entry.errors[:level], "Log level must be 'info', 'warning', or 'error'"
  end

  test "scopes filter by level" do
    assert_includes CrawlLogEntry.errors, crawl_log_entries(:error_entry)
    refute_includes CrawlLogEntry.errors, crawl_log_entries(:info_entry)
    assert_includes CrawlLogEntry.infos, crawl_log_entries(:info_entry)
  end

  test "to_log_line includes timestamp, level, company, and message" do
    entry = crawl_log_entries(:error_entry)
    line = entry.to_log_line

    assert_includes line, entry.level.upcase
    assert_includes line, entry.company
    assert_includes line, entry.message
    assert_includes line, "retry 3"
  end

  test "css_class maps level to a CSS class" do
    assert_equal "log-error",   CrawlLogEntry.new(level: "error").css_class
    assert_equal "log-warning", CrawlLogEntry.new(level: "warning").css_class
    assert_equal "log-info",    CrawlLogEntry.new(level: "info").css_class
  end

  test "emoji_prefix maps level to an emoji" do
    assert_equal "🔴", CrawlLogEntry.new(level: "error").emoji_prefix
    assert_equal "🟡", CrawlLogEntry.new(level: "warning").emoji_prefix
    assert_equal "🟢", CrawlLogEntry.new(level: "info").emoji_prefix
  end
end
