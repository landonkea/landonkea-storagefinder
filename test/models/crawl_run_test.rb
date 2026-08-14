# Loads test/test_helper.rb, which boots the Rails app in test mode and sets
# up shared test infrastructure (Minitest, Ruby's automated-testing
# framework, fixture loading, etc.). See test/test_helper.rb or
# test/models/alert_rule_test.rb for a fuller explanation.
require "test_helper"

# An automated test suite for the CrawlRun model (see
# app/models/crawl_run.rb). `class CrawlRunTest < ActiveSupport::TestCase`
# inherits from Rails' base test class, which provides the `test "..." do
# ... end` syntax below, the `assert_*`/`refute_*` assertion methods, and
# fixture lookups like `crawl_runs(:...)`.
class CrawlRunTest < ActiveSupport::TestCase
  # `test "..." do ... end` defines one individual automated test (see
  # test/models/alert_rule_test.rb for a full explanation of this Rails/
  # Minitest syntax). Each block below is one self-contained check.
  test "start! marks the crawl as running and logs it" do
    # `CrawlRun.create!(...)` builds AND immediately saves a new CrawlRun
    # record to the test database in one step (unlike `.new`, which only
    # builds it in memory). The `!` means it raises an error if validation
    # fails, instead of silently returning false. This test builds its own
    # fresh record from scratch (rather than using a fixture) because it
    # needs to start from `status: "pending"` and then call `start!` on it.
    crawl_run = CrawlRun.create!(search_city: "Test City", search_radius_miles: 25, status: "pending")
    # Calls the `start!` instance method (see app/models/crawl_run.rb),
    # which updates status to "running", stamps `started_at`, and writes a
    # log entry.
    crawl_run.start!

    # `assert_equal expected, actual` fails unless the two values are
    # exactly equal. `crawl_run.status` re-reads the in-memory attribute,
    # `update!` (used inside start!) updates the Ruby object's attributes
    # as well as the database, so no explicit reload is needed here.
    assert_equal "running", crawl_run.status
    # `assert_not_nil` fails unless the value is anything other than nil,
    # confirms `started_at` actually got stamped with a timestamp.
    assert_not_nil crawl_run.started_at
    # `crawl_run.crawl_log_entries` follows the `has_many :crawl_log_entries`
    # association (see app/models/crawl_run.rb) to query this crawl run's
    # log entries. `.exists?(message: "Crawl started")` runs an efficient
    # SQL existence check for a log entry with that exact message, start!
    # calls `log_info("Crawl started", ...)` internally, so this confirms
    # that log entry was actually created and saved.
    assert crawl_run.crawl_log_entries.exists?(message: "Crawl started")
  end
  # `end` closes this `test` block.

  test "complete! marks completed, sets duration, and logs it" do
    # Builds a crawl run that's already "running" and already has a
    # `started_at` timestamp, so that calling `complete!` below has
    # something to compute a duration FROM.
    #
    # `5.minutes.ago` is a Rails/ActiveSupport method chain: `5.minutes`
    # converts the plain integer 5 into a Duration object representing "5
    # minutes," and `.ago` subtracts that duration from the current time,
    # giving a Time object 5 minutes in the past. This lets the test
    # simulate "the crawl started 5 minutes ago" without waiting 5 real
    # minutes.
    crawl_run = CrawlRun.create!(
      search_city: "Test City", search_radius_miles: 25, status: "running",
      started_at: 5.minutes.ago, facilities_found: 3, units_found: 10
    )
    # Calls the `complete!` instance method (see app/models/crawl_run.rb),
    # which computes `now - started_at` as the duration, then updates
    # status, `completed_at`, and `duration_seconds`, and writes a log entry.
    crawl_run.complete!

    assert_equal "completed", crawl_run.status
    assert_not_nil crawl_run.completed_at
    # `assert_in_delta expected, actual, tolerance` is a Minitest assertion
    # for comparing NUMBERS that might not be exactly equal due to timing,
    # since started_at was set to "5 minutes ago" at record-creation time,
    # and complete! runs a few moments after that, the ACTUAL elapsed
    # seconds will be slightly more than exactly 300 (5 minutes). This
    # assertion passes as long as `crawl_run.duration_seconds` is within 5
    # seconds of 300, a plain `assert_equal 300, ...` would be too strict
    # and flaky here.
    assert_in_delta 300, crawl_run.duration_seconds, 5
  end
  # `end` closes this `test` block.

  test "fail! marks failed and records the error message" do
    crawl_run = CrawlRun.create!(search_city: "Test City", search_radius_miles: 25, status: "running")
    # `fail!(message)` (see app/models/crawl_run.rb) is a required
    # positional argument, the error text describing why the crawl failed.
    # It updates status to "failed", stamps completed_at, stores the
    # message, and writes an ERROR-level log entry.
    crawl_run.fail!("Something went wrong")

    assert_equal "failed", crawl_run.status
    assert_equal "Something went wrong", crawl_run.error_message
    # Confirms an error-level log entry was created as a side effect of
    # fail! (it calls `log_error`, not `log_info`).
    assert crawl_run.crawl_log_entries.exists?(level: "error")
  end
  # `end` closes this `test` block.

  test "increment_* counters are additive" do
    crawl_run = CrawlRun.create!(search_city: "Test City", search_radius_miles: 25, status: "running")

    # Each of these calls an `increment_*!` instance method defined in
    # app/models/crawl_run.rb, which uses Rails' `increment!` under the hood
    # to atomically add to a counter column and save immediately.
    # `increment_facilities!(3)` adds 3, then `increment_facilities!(2)`
    # adds 2 more, together they should total 5.
    crawl_run.increment_facilities!(3)
    crawl_run.increment_facilities!(2)
    # `increment_units!(10)` adds 10 to units_found in one call.
    crawl_run.increment_units!(10)
    # These two take no argument, the underlying `increment!` call
    # defaults to adding 1 when no amount is given.
    crawl_run.increment_companies_crawled!
    crawl_run.increment_companies_failed!

    # `crawl_run.reload` re-fetches every attribute fresh FROM THE DATABASE.
    # This is a good habit here even though `increment!` also updates the
    # in-memory object, because it proves the values were actually
    # PERSISTED (saved) correctly, not just held in Ruby memory.
    crawl_run.reload
    assert_equal 5, crawl_run.facilities_found
    assert_equal 10, crawl_run.units_found
    assert_equal 1, crawl_run.companies_crawled
    assert_equal 1, crawl_run.companies_failed
  end
  # `end` closes this `test` block.

  test "running? and finished? reflect status" do
    # `crawl_runs(:running_crawl)` is a FIXTURE lookup: fixtures are
    # pre-made, fake database rows defined in YAML files under
    # test/fixtures/ (here, test/fixtures/crawl_runs.yml), automatically
    # loaded into the test database before every test runs. This returns
    # the real, already-saved CrawlRun built from the `running_crawl:`
    # entry in that file (status: "running").
    #
    # `.running?` and `.finished?` are instance methods on CrawlRun (see
    # app/models/crawl_run.rb) that check the `status` column. `assert
    # crawl_runs(:running_crawl).running?` fails unless calling
    # `.running?` on that fixture returns something truthy.
    assert crawl_runs(:running_crawl).running?
    # A running crawl is NOT yet finished, `finished?` should be false.
    refute crawl_runs(:running_crawl).finished?

    # `crawl_runs(:current_completed)` loads a different fixture whose
    # status is "completed", the opposite expectations should hold.
    assert crawl_runs(:current_completed).finished?
    refute crawl_runs(:current_completed).running?

    # `crawl_runs(:failed_crawl)` has status "failed", finished? treats
    # both "completed" and "failed" as finished (see
    # `%w[completed failed].include?(status)` in app/models/crawl_run.rb).
    assert crawl_runs(:failed_crawl).finished?
  end
  # `end` closes this `test` block.

  test "duration_label formats seconds into a readable string" do
    # `.dup` creates a DUPLICATE (shallow copy) of the fixture object, an
    # independent, unsaved-changes copy, so this test can freely mutate its
    # `duration_seconds` attribute below without affecting the original
    # fixture record other tests might rely on. Since `crawl_run` here is
    # never saved again, these attribute changes only exist in memory for
    # the rest of this test.
    crawl_run = crawl_runs(:current_completed).dup

    # Sets duration_seconds to nil to test the "crawl never finished" case.
    crawl_run.duration_seconds = nil
    # `duration_label` (see app/models/crawl_run.rb) returns "Not finished"
    # when duration_seconds is nil.
    assert_equal "Not finished", crawl_run.duration_label

    # 0.4 seconds is less than 1 whole second, duration_label has a
    # special-cased friendly message for this instead of printing "0
    # seconds".
    crawl_run.duration_seconds = 0.4
    assert_equal "Less than 1 second", crawl_run.duration_label

    # 45 seconds is under a minute, no "minutes" portion should appear.
    crawl_run.duration_seconds = 45
    assert_equal "45 seconds", crawl_run.duration_label

    # 125 seconds = 2 minutes and 5 seconds (125 = 2*60 + 5), checks both
    # the minutes/seconds math AND correct pluralization ("minutes",
    # "seconds").
    crawl_run.duration_seconds = 125
    assert_equal "2 minutes and 5 seconds", crawl_run.duration_label

    # 61 seconds = 1 minute and 1 second (61 = 1*60 + 1), checks the
    # SINGULAR form ("minute", "second" with no trailing "s") is used
    # correctly when the count is exactly 1.
    crawl_run.duration_seconds = 61
    assert_equal "1 minute and 1 second", crawl_run.duration_label
  end
  # `end` closes this `test` block.

  test "summary describes each status" do
    # Loads three different fixtures with different statuses to check
    # `summary` (see app/models/crawl_run.rb) produces the right text for
    # each branch of its `case status` statement.
    completed = crawl_runs(:current_completed)
    # `assert_match(regexp, string)` checks a Regexp (regular expression,
    # a pattern for matching text) matches somewhere in the string.
    # `/facilities.*units/` matches any string containing "facilities",
    # then ANY characters (`.` means "any character", `*` means "zero or
    # more of the previous thing"), then "units", i.e. it checks both
    # words appear, in that order, without pinning down the exact numbers
    # or wording in between.
    assert_match(/facilities.*units/, completed.summary)

    failed = crawl_runs(:failed_crawl)
    # `/^FAILED:/` matches "FAILED:" specifically at the START of the
    # string, `^` is a regex anchor meaning "beginning of line", checking
    # the failed-status summary is prefixed this way.
    assert_match(/^FAILED:/, failed.summary)

    running = crawl_runs(:running_crawl)
    # Similarly, `^Running` checks the running-status summary starts with
    # the word "Running".
    assert_match(/^Running/, running.summary)

    # `CrawlRun.new(status: "pending")` builds a brand-new, UNSAVED record
    # (not a fixture) with only `status` set, enough to exercise the
    # "pending" branch of `summary`, which returns a fixed string regardless
    # of any other attribute.
    pending = CrawlRun.new(status: "pending")
    assert_equal "Waiting to start", pending.summary
  end
  # `end` closes this `test` block.

  test "log_info/log_warning/log_error/log_success create tagged log entries" do
    crawl_run = crawl_runs(:current_completed)

    # Calls each of the four logging helper methods (see
    # app/models/crawl_run.rb) with a distinct message per level, plus the
    # required `company:` keyword argument. Each one creates and saves a
    # CrawlLogEntry associated with this crawl_run.
    crawl_run.log_info("info message", company: "Test Co")
    crawl_run.log_warning("warning message", company: "Test Co")
    crawl_run.log_error("error message", company: "Test Co")
    # `log_success` both creates an info-level entry AND marks its
    # `success` column true, then returns that entry, captured here in the
    # local variable `success_entry` so it can be checked below.
    success_entry = crawl_run.log_success("success message", company: "Test Co")

    # For each of the first three, checks a matching log entry (both the
    # right level AND the right message text) actually exists in the
    # database via the has_many association.
    assert crawl_run.crawl_log_entries.exists?(level: "info", message: "info message")
    assert crawl_run.crawl_log_entries.exists?(level: "warning", message: "warning message")
    assert crawl_run.crawl_log_entries.exists?(level: "error", message: "error message")
    # `success_entry.success?` is Rails' automatically-generated boolean
    # query method for the `success` column, confirms log_success actually
    # flipped it to true (rather than leaving it nil/false).
    assert success_entry.success?
  end
  # `end` closes this `test` block.

  test "any_running? and running scope" do
    # `CrawlRun.any_running?` is a CLASS method (see app/models/crawl_run.rb,
    # `def self.any_running?`) checking whether ANY crawl run currently has
    # status "running", true here because the running_crawl fixture (see
    # test/fixtures/crawl_runs.yml) is loaded into the test database before
    # this test runs.
    assert CrawlRun.any_running?
    # `CrawlRun.running` is the `running` SCOPE (a query, not the class
    # method above), checks the running_crawl fixture is included in its
    # results.
    assert_includes CrawlRun.running, crawl_runs(:running_crawl)
  end
  # `end` closes this `test` block.

  test "latest_completed returns the most recently completed run" do
    # `CrawlRun.latest_completed` (see app/models/crawl_run.rb) finds the
    # single most-recently-completed run by `completed_at`. Two completed
    # fixtures exist, previous_completed and current_completed (see
    # test/fixtures/crawl_runs.yml), with current_completed's completed_at
    # timestamp being more recent, so it should be the one returned.
    # `assert_equal` on two ActiveRecord objects compares them by their
    # class AND database id, so this confirms it's the SAME database row.
    assert_equal crawl_runs(:current_completed), CrawlRun.latest_completed
  end
  # `end` closes this `test` block.

  test "history scopes to the given number of months" do
    # `CrawlRun.history(months: 6)` calls the class method (see
    # app/models/crawl_run.rb) with an explicit keyword argument, returning
    # every crawl run created within the last 6 months.
    within_range = CrawlRun.history(months: 6)
    # Both completed fixtures were created a few days ago (per their
    # `created_at: <%= ... %>` values in test/fixtures/crawl_runs.yml), well
    # within a 6-month window, so both should be included.
    assert_includes within_range, crawl_runs(:current_completed)
    assert_includes within_range, crawl_runs(:previous_completed)

    # Builds a brand-new record with `created_at:` explicitly forced far in
    # the past. `2.years.ago` is the same `n.units.ago` pattern used earlier
    # in this file (`5.minutes.ago`), here producing a Time two years back.
    # Note: normally Rails overwrites `created_at` automatically on create,
    # but ActiveRecord lets you explicitly pass it in `create!` to override
    # that default, which is exactly what's needed to simulate an old
    # record here.
    old_run = CrawlRun.create!(
      search_city: "Ancient", search_radius_miles: 10, status: "completed",
      created_at: 2.years.ago
    )
    # A record from 2 years ago falls OUTSIDE a 6-month history window, so
    # it should be excluded.
    refute_includes CrawlRun.history(months: 6), old_run
  end
  # `end` closes this `test` block.

  test "status must be one of the known values" do
    # `CrawlRun.new(status: "bogus", search_radius_miles: 10)` builds an
    # unsaved record with a status not in the model's allowed list
    # (`%w[pending running completed failed]` in app/models/crawl_run.rb).
    crawl_run = CrawlRun.new(status: "bogus", search_radius_miles: 10)
    refute crawl_run.valid?
    assert_includes crawl_run.errors[:status], "Status must be one of: pending, running, completed, failed"
  end
  # `end` closes this `test` block.
end
# `end` closes the `class CrawlRunTest < ActiveSupport::TestCase` block that
# started at the top of this file.
