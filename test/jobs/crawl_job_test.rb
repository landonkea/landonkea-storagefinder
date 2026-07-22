require "test_helper"

# CrawlJob's core loop launches a real Playwright browser and drives real
# company-parser network calls — not something to fake convincingly in a
# unit test without a browser test double, which is a bigger undertaking
# than this pass covers. This tests the guard clauses and error paths that
# run before Playwright is ever launched: duplicate-run protection,
# geocoding failure, and "Playwright CLI not found."
class CrawlJobTest < ActiveJob::TestCase
  test "refuses to run a second time if the crawl is already running" do
    crawl_run = crawl_runs(:running_crawl)

    # Should return immediately without raising or re-starting anything —
    # started_at should stay exactly as the fixture set it.
    original_started_at = crawl_run.started_at
    CrawlJob.perform_now(crawl_run_id: crawl_run.id, options: {})

    assert_equal original_started_at.to_i, crawl_run.reload.started_at.to_i
  end

  test "fails the crawl cleanly when geocoding finds no coordinates" do
    crawl_run = CrawlRun.create!(search_city: "Nowhere At All Zzzz", search_radius_miles: 25, status: "pending")

    Geocoder::Lookup::Test.set_default_stub([]) # simulate "no results"
    CrawlJob.perform_now(crawl_run_id: crawl_run.id, options: {})

    crawl_run.reload
    assert_equal "failed", crawl_run.status
    assert_match(/Could not find coordinates/, crawl_run.error_message)
  ensure
    # Restore the default stub other tests (and Facility's auto-geocode) rely on.
    Geocoder::Lookup::Test.set_default_stub(
      [ { "coordinates" => [ 33.3528, -111.7890 ], "address" => "Gilbert, AZ, USA",
         "state" => "Arizona", "state_code" => "AZ", "country" => "United States", "country_code" => "US" } ]
    )
  end

  test "fails the crawl cleanly when the Playwright CLI can't be found" do
    crawl_run = CrawlRun.create!(search_city: "Gilbert, Arizona", search_radius_miles: 25, status: "pending")

    stub_any_instance(CrawlJob, :`, ->(*) { "" }) do
      CrawlJob.perform_now(crawl_run_id: crawl_run.id, options: {})
    end

    crawl_run.reload
    assert_equal "failed", crawl_run.status
    assert_match(/Playwright CLI not found/, crawl_run.error_message)
  end

  test "silently returns (without raising) if the CrawlRun record was deleted before the job ran" do
    assert_no_difference "CrawlRun.count" do
      CrawlJob.perform_now(crawl_run_id: 999_999, options: {})
    end
  end
end
