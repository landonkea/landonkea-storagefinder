# `require "test_helper"` loads test/test_helper.rb, which boots Rails in
# test mode, stubs Geocoder so this file's tests don't hit the real network
# for geocoding, and defines the `stub_any_instance` helper used below to
# fake out the backtick shell-command call in CrawlJob.
require "test_helper"

# CrawlJob's core loop launches a real Playwright browser and drives real
# company-parser network calls — not something to fake convincingly in a
# unit test without a browser test double, which is a bigger undertaking
# than this pass covers. This tests the guard clauses and error paths that
# run before Playwright is ever launched: duplicate-run protection,
# geocoding failure, and "Playwright CLI not found."
#
# `class CrawlJobTest < ActiveJob::TestCase` — this inherits from
# ActiveJob::TestCase rather than plain ActiveSupport::TestCase. It's a
# Rails-provided base class specifically for testing ActiveJob jobs: it
# still gives you fixtures and standard assertions (via its own
# inheritance from ActiveSupport::TestCase under the hood), but ALSO adds
# job-specific assertion helpers (like `assert_enqueued_jobs`,
# `assert_no_difference` used below, and others not used in this file) that
# understand ActiveJob's queueing/enqueuing behavior.
class CrawlJobTest < ActiveJob::TestCase
  test "refuses to run a second time if the crawl is already running" do
    # `crawl_runs(:running_crawl)` looks up the CrawlRun fixture named
    # "running_crawl" (see test/fixtures/crawl_runs.yml) — a crawl that's
    # already mid-run according to its `status` column.
    crawl_run = crawl_runs(:running_crawl)

    # Should return immediately without raising or re-starting anything —
    # started_at should stay exactly as the fixture set it.
    # Saves the fixture's original `started_at` timestamp before running the
    # job, so it can be compared against afterward.
    original_started_at = crawl_run.started_at
    # `CrawlJob.perform_now(...)` runs the job synchronously right here,
    # rather than merely enqueuing it. `options: {}` matches CrawlJob#perform's
    # required keyword argument (see app/jobs/crawl_job.rb) — an empty hash
    # here means "no company/filter options," which is fine since this test
    # expects the job to bail out before it would ever use them.
    CrawlJob.perform_now(crawl_run_id: crawl_run.id, options: {})

    # `.to_i` converts each Time to an integer (Unix timestamp, seconds
    # since epoch) before comparing — this avoids spurious test failures
    # from sub-second precision differences between how the value was
    # originally stored versus how it's read back from the database.
    # `crawl_run.reload` re-fetches the row from the database so this
    # reflects whatever CrawlJob actually did (or, as expected here, didn't
    # do) to it.
    assert_equal original_started_at.to_i, crawl_run.reload.started_at.to_i
  end
  # `end` closes the "refuses to run a second time..." test block above.

  test "fails the crawl cleanly when geocoding finds no coordinates" do
    # `CrawlRun.create!(...)` builds a brand-new CrawlRun row directly
    # (the trailing `!` raises an exception instead of silently returning
    # false if it fails validation). `status: "pending"` means it hasn't
    # started yet, so CrawlJob's "already running?" guard (tested above)
    # won't short-circuit this test.
    crawl_run = CrawlRun.create!(search_city: "Nowhere At All Zzzz", search_radius_miles: 25, status: "pending")

    # `Geocoder::Lookup::Test.set_default_stub([])` overrides — just for
    # this test — the fake geocoding result test_helper.rb configured at
    # boot, replacing it with an EMPTY array. An empty array is exactly
    # what Geocoder returns when a real lookup finds no matching location,
    # so this simulates "the search city couldn't be found" without
    # touching the real network.
    Geocoder::Lookup::Test.set_default_stub([]) # simulate "no results"
    CrawlJob.perform_now(crawl_run_id: crawl_run.id, options: {})

    crawl_run.reload
    # `assert_equal "failed", crawl_run.status` confirms the job marked
    # this crawl as failed rather than, say, silently doing nothing or
    # crashing the whole job process.
    assert_equal "failed", crawl_run.status
    # `assert_match(/Could not find coordinates/, crawl_run.error_message)`
    # checks that the saved error message CONTAINS this text, using a Ruby
    # Regexp literal (the `/.../ ` slashes mark a regular expression — a
    # pattern-matching search, here just matching literal text with no
    # special pattern characters) rather than requiring an exact string
    # match — useful because the full message also includes the city name
    # and a suggestion, which this test doesn't care about checking.
    assert_match(/Could not find coordinates/, crawl_run.error_message)
  # `ensure` runs this cleanup no matter how the test above finished
  # (pass, fail, or raise) — without it, the empty-array stub set above
  # would leak into every test that runs after this one in the same
  # process, breaking Facility's auto-geocode-on-save in totally unrelated
  # tests.
  ensure
    # Restore the default stub other tests (and Facility's auto-geocode) rely on.
    # Rebuilds the same fake successful-geocode response test_helper.rb set
    # up originally, so later tests get a working stub again.
    Geocoder::Lookup::Test.set_default_stub(
      [ { "coordinates" => [ 33.3528, -111.7890 ], "address" => "Gilbert, AZ, USA",
         "state" => "Arizona", "state_code" => "AZ", "country" => "United States", "country_code" => "US" } ]
    )
  end
  # `end` closes the "fails the crawl cleanly when geocoding finds no
  # coordinates" test block above (the `ensure` clause is part of this same
  # test block, not a separate one).

  test "fails the crawl cleanly when the Playwright CLI can't be found" do
    crawl_run = CrawlRun.create!(search_city: "Gilbert, Arizona", search_radius_miles: 25, status: "pending")

    # `stub_any_instance(CrawlJob, :`, ->(*) { "" }) do ... end` uses the
    # custom helper defined in test_helper.rb. It temporarily replaces the
    # backtick method (written here as the Symbol `:\``, i.e. the method
    # literally named backtick) on EVERY instance of CrawlJob. In Ruby,
    # backtick-quoted text like `` `some shell command` `` is actually
    # calling a real method named backtick — CrawlJob uses it to shell out
    # and look for the Playwright CLI (see app/jobs/crawl_job.rb). The fake
    # implementation `->(*) { "" }` is a lambda that accepts ANY arguments
    # (the `*` "splat" means "ignore however many args come in") and always
    # returns an empty string — simulating "the shell command found
    # nothing," i.e. Playwright isn't installed, without actually running
    # any real shell command or depending on whether Playwright happens to
    # be installed on the machine running this test.
    stub_any_instance(CrawlJob, :`, ->(*) { "" }) do
      # This is the block yielded to by stub_any_instance — the actual test
      # code that runs WHILE the backtick method is faked. CrawlJob.perform_now
      # runs here, and every internal backtick call it makes returns "".
      CrawlJob.perform_now(crawl_run_id: crawl_run.id, options: {})
    end
    # `end` closes the `stub_any_instance(...) do ... end` block above —
    # once this line runs, CrawlJob's real backtick method has already been
    # restored (stub_any_instance's `ensure` guarantees that).

    crawl_run.reload
    assert_equal "failed", crawl_run.status
    assert_match(/Playwright CLI not found/, crawl_run.error_message)
  end
  # `end` closes the "fails the crawl cleanly when the Playwright CLI can't
  # be found" test block above.

  test "silently returns (without raising) if the CrawlRun record was deleted before the job ran" do
    # `assert_no_difference "CrawlRun.count" do ... end` is a Rails/ActiveSupport
    # assertion helper: it evaluates "CrawlRun.count" (as a string of Ruby
    # code, via eval) BEFORE running the block, runs the block, evaluates
    # "CrawlRun.count" again AFTERWARD, and fails the test if those two
    # counts differ. Here it confirms the job neither creates nor deletes
    # any CrawlRun rows when given an ID that doesn't exist.
    assert_no_difference "CrawlRun.count" do
      # `crawl_run_id: 999_999` is a made-up ID that (almost certainly)
      # doesn't correspond to any real row — the underscore in `999_999`
      # is just a Ruby readability separator for large numbers and has no
      # effect on the value, exactly like a comma in "999,999". This
      # exercises CrawlJob's `rescue ActiveRecord::RecordNotFound` branch
      # (see app/jobs/crawl_job.rb), which logs the problem and returns
      # instead of letting the exception crash the job.
      CrawlJob.perform_now(crawl_run_id: 999_999, options: {})
    end
    # `end` closes the `assert_no_difference "CrawlRun.count" do` block above.
  end
  # `end` closes the "silently returns...record was deleted" test block above.
end
# `end` closes the `class CrawlJobTest < ActiveJob::TestCase` definition
# that started at the top of this file.
