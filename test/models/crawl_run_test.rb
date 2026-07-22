require "test_helper"

class CrawlRunTest < ActiveSupport::TestCase
  test "start! marks the crawl as running and logs it" do
    crawl_run = CrawlRun.create!(search_city: "Test City", search_radius_miles: 25, status: "pending")
    crawl_run.start!

    assert_equal "running", crawl_run.status
    assert_not_nil crawl_run.started_at
    assert crawl_run.crawl_log_entries.exists?(message: "Crawl started")
  end

  test "complete! marks completed, sets duration, and logs it" do
    crawl_run = CrawlRun.create!(
      search_city: "Test City", search_radius_miles: 25, status: "running",
      started_at: 5.minutes.ago, facilities_found: 3, units_found: 10
    )
    crawl_run.complete!

    assert_equal "completed", crawl_run.status
    assert_not_nil crawl_run.completed_at
    assert_in_delta 300, crawl_run.duration_seconds, 5
  end

  test "fail! marks failed and records the error message" do
    crawl_run = CrawlRun.create!(search_city: "Test City", search_radius_miles: 25, status: "running")
    crawl_run.fail!("Something went wrong")

    assert_equal "failed", crawl_run.status
    assert_equal "Something went wrong", crawl_run.error_message
    assert crawl_run.crawl_log_entries.exists?(level: "error")
  end

  test "increment_* counters are additive" do
    crawl_run = CrawlRun.create!(search_city: "Test City", search_radius_miles: 25, status: "running")

    crawl_run.increment_facilities!(3)
    crawl_run.increment_facilities!(2)
    crawl_run.increment_units!(10)
    crawl_run.increment_companies_crawled!
    crawl_run.increment_companies_failed!

    crawl_run.reload
    assert_equal 5, crawl_run.facilities_found
    assert_equal 10, crawl_run.units_found
    assert_equal 1, crawl_run.companies_crawled
    assert_equal 1, crawl_run.companies_failed
  end

  test "running? and finished? reflect status" do
    assert crawl_runs(:running_crawl).running?
    refute crawl_runs(:running_crawl).finished?

    assert crawl_runs(:current_completed).finished?
    refute crawl_runs(:current_completed).running?

    assert crawl_runs(:failed_crawl).finished?
  end

  test "duration_label formats seconds into a readable string" do
    crawl_run = crawl_runs(:current_completed).dup

    crawl_run.duration_seconds = nil
    assert_equal "Not finished", crawl_run.duration_label

    crawl_run.duration_seconds = 0.4
    assert_equal "Less than 1 second", crawl_run.duration_label

    crawl_run.duration_seconds = 45
    assert_equal "45 seconds", crawl_run.duration_label

    crawl_run.duration_seconds = 125
    assert_equal "2 minutes and 5 seconds", crawl_run.duration_label

    crawl_run.duration_seconds = 61
    assert_equal "1 minute and 1 second", crawl_run.duration_label
  end

  test "summary describes each status" do
    completed = crawl_runs(:current_completed)
    assert_match(/facilities.*units/, completed.summary)

    failed = crawl_runs(:failed_crawl)
    assert_match(/^FAILED:/, failed.summary)

    running = crawl_runs(:running_crawl)
    assert_match(/^Running/, running.summary)

    pending = CrawlRun.new(status: "pending")
    assert_equal "Waiting to start", pending.summary
  end

  test "log_info/log_warning/log_error/log_success create tagged log entries" do
    crawl_run = crawl_runs(:current_completed)

    crawl_run.log_info("info message", company: "Test Co")
    crawl_run.log_warning("warning message", company: "Test Co")
    crawl_run.log_error("error message", company: "Test Co")
    success_entry = crawl_run.log_success("success message", company: "Test Co")

    assert crawl_run.crawl_log_entries.exists?(level: "info", message: "info message")
    assert crawl_run.crawl_log_entries.exists?(level: "warning", message: "warning message")
    assert crawl_run.crawl_log_entries.exists?(level: "error", message: "error message")
    assert success_entry.success?
  end

  test "any_running? and running scope" do
    assert CrawlRun.any_running?
    assert_includes CrawlRun.running, crawl_runs(:running_crawl)
  end

  test "latest_completed returns the most recently completed run" do
    assert_equal crawl_runs(:current_completed), CrawlRun.latest_completed
  end

  test "history scopes to the given number of months" do
    within_range = CrawlRun.history(months: 6)
    assert_includes within_range, crawl_runs(:current_completed)
    assert_includes within_range, crawl_runs(:previous_completed)

    old_run = CrawlRun.create!(
      search_city: "Ancient", search_radius_miles: 10, status: "completed",
      created_at: 2.years.ago
    )
    refute_includes CrawlRun.history(months: 6), old_run
  end

  test "status must be one of the known values" do
    crawl_run = CrawlRun.new(status: "bogus", search_radius_miles: 10)
    refute crawl_run.valid?
    assert_includes crawl_run.errors[:status], "Status must be one of: pending, running, completed, failed"
  end
end
