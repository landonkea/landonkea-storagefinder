# `require "test_helper"` loads test/test_helper.rb, see the fuller
# explanation of this line in test/jobs/alert_checker_job_test.rb.
require "test_helper"

# This file tests ScheduledCrawlCheckJob (app/jobs/scheduled_crawl_check_job.rb)
#, the job that wires the schedule_enabled/schedule_cron/schedule_city/
# schedule_radius_miles Setting rows up to an actual triggered crawl. See
# that job's own top comment for the full "why" behind how it's built.
class ScheduledCrawlCheckJobTest < ActiveSupport::TestCase
  # `include ActiveSupport::Testing::TimeHelpers` adds `travel_to`, used
  # below to pin "the current time" to an exact, known moment for each test
  #, without this, whether a given cron expression "matches now" would
  # depend on the literal wall-clock second the test happens to run, making
  # these tests flaky.
  include ActiveSupport::Testing::TimeHelpers
  # `include ActiveJob::TestHelper` adds `assert_enqueued_with` and
  # `assert_no_enqueued_jobs`, used below to check whether CrawlJob got
  # enqueued without actually running it (this test suite otherwise never
  # needed these helpers, since AlertCheckerJob's own test file, see
  # test/jobs/alert_checker_job_test.rb, only ever calls jobs directly,
  # never asserts on what they enqueue).
  include ActiveJob::TestHelper

  setup do
    # test/fixtures/crawl_runs.yml includes one fixture with status
    # "running" (used elsewhere to test in-progress-crawl behavior), that
    # would make CrawlRun.any_running? true by default here, which isn't
    # what most of these tests want to check. Reset it to "completed" so
    # each test starts from a clean "nothing running" baseline; the one
    # test that specifically wants a crawl in progress sets a fixture back
    # to "running" itself.
    CrawlRun.where(status: "running").update_all(status: "completed")
  end

  test "does nothing when schedule_enabled is false" do
    Setting.set("schedule_enabled", "false")
    Setting.set("schedule_cron", "* * * * *") # would match any minute if checked

    assert_no_difference "CrawlRun.count" do
      ScheduledCrawlCheckJob.perform_now
    end
    assert_no_enqueued_jobs(only: CrawlJob)
  end

  test "triggers a crawl when enabled and the cron expression matches the current minute" do
    Setting.set("schedule_enabled", "true")
    Setting.set("schedule_cron", "30 6 * * *")
    # A city name that doesn't collide with any test/fixtures/crawl_runs.yml
    # fixture, so looking it up below unambiguously finds the row this test
    # created (not some pre-existing fixture that happens to share a city).
    Setting.set("schedule_city", "Scottsdale, Arizona")
    Setting.set("schedule_radius_miles", "50")

    travel_to Time.zone.local(2026, 1, 5, 6, 30, 0) do
      assert_difference "CrawlRun.count", 1 do
        assert_enqueued_with(job: CrawlJob) do
          ScheduledCrawlCheckJob.perform_now
        end
      end
    end

    # Looked up by the distinctive city above rather than
    # `CrawlRun.order(:created_at).last`, since `travel_to` above pins the
    # job's own idea of "now" to January 2026 while fixture rows keep their
    # real (later) created_at timestamps, ordering by created_at would
    # find a fixture, not the row this test just created.
    crawl_run = CrawlRun.find_by!(search_city: "Scottsdale, Arizona")
    assert_equal 50, crawl_run.search_radius_miles
    assert_equal "pending", crawl_run.status
  end

  test "does nothing when enabled but the cron expression does not match the current minute" do
    Setting.set("schedule_enabled", "true")
    Setting.set("schedule_cron", "30 6 * * *")

    travel_to Time.zone.local(2026, 1, 5, 6, 31, 0) do
      assert_no_difference "CrawlRun.count" do
        ScheduledCrawlCheckJob.perform_now
      end
    end
    assert_no_enqueued_jobs(only: CrawlJob)
  end

  test "skips when a crawl is already running, even if the schedule matches" do
    Setting.set("schedule_enabled", "true")
    Setting.set("schedule_cron", "* * * * *")
    crawl_runs(:previous_completed).update!(status: "running")

    assert_no_difference "CrawlRun.count" do
      ScheduledCrawlCheckJob.perform_now
    end
    assert_no_enqueued_jobs(only: CrawlJob)
  end

  test "falls back to the most recent crawl's search city when schedule_city is blank" do
    Setting.set("schedule_enabled", "true")
    Setting.set("schedule_cron", "* * * * *")
    Setting.set("schedule_city", "")

    last_city = CrawlRun.recent.first.search_city

    assert_difference "CrawlRun.count", 1 do
      ScheduledCrawlCheckJob.perform_now
    end

    assert_equal last_city, CrawlRun.order(:created_at).last.search_city
  end

  test "does nothing when schedule_city is blank and there is no previous crawl to fall back on" do
    CrawlRun.destroy_all
    Setting.set("schedule_enabled", "true")
    Setting.set("schedule_cron", "* * * * *")
    Setting.set("schedule_city", "")

    assert_no_difference "CrawlRun.count" do
      ScheduledCrawlCheckJob.perform_now
    end
    assert_no_enqueued_jobs(only: CrawlJob)
  end

  test "logs an error and does nothing when schedule_cron is not valid cron syntax" do
    Setting.set("schedule_enabled", "true")
    Setting.set("schedule_cron", "not a cron expression")

    assert_no_difference "CrawlRun.count" do
      ScheduledCrawlCheckJob.perform_now
    end
    assert_no_enqueued_jobs(only: CrawlJob)
  end
end
