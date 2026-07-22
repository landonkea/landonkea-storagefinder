require "test_helper"

class CrawlsControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues a crawl job and redirects" do
    CrawlRun.where(status: "running").destroy_all # any_running? must be false

    assert_enqueued_with(job: CrawlJob) do
      post crawls_path, params: { search_city: "Tempe, Arizona", radius_miles: "50" }
    end

    assert_redirected_to root_path
    assert_equal "Tempe, Arizona", CrawlRun.order(:created_at).last.search_city
  end

  test "create refuses to start a second crawl while one is already running" do
    assert CrawlRun.any_running?

    post crawls_path, params: { search_city: "Tempe, Arizona", radius_miles: "50" }

    assert_redirected_to root_path
    assert_equal "A crawl is already running. Please wait for it to finish before starting a new one.", flash[:alert]
  end

  test "create requires a search city" do
    CrawlRun.where(status: "running").destroy_all

    post crawls_path, params: { search_city: "", radius_miles: "50" }

    assert_redirected_to root_path
    assert_match(/enter a city name/, flash[:alert])
  end

  test "create rejects an out-of-range radius" do
    CrawlRun.where(status: "running").destroy_all

    post crawls_path, params: { search_city: "Tempe, Arizona", radius_miles: "9999" }

    assert_redirected_to root_path
    assert_match(/Radius must be between/, flash[:alert])
  end

  test "show renders the crawl's log entries" do
    get crawl_path(crawl_runs(:previous_completed))
    assert_response :success
  end

  test "show redirects with an alert when the crawl doesn't exist" do
    get crawl_path(id: 999_999)
    assert_redirected_to root_path
    assert_match(/not found/, flash[:alert])
  end

  test "log returns JSON entries newer than since_id" do
    crawl_run = crawl_runs(:previous_completed)
    older = crawl_log_entries(:info_entry)
    newer = crawl_run.crawl_log_entries.create!(company: "system", level: "info", message: "newer entry")

    get log_crawl_path(crawl_run), params: { since_id: older.id }, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    ids = body["entries"].map { |e| e["id"] }
    assert_includes ids, newer.id
    refute_includes ids, older.id
  end

  test "destroy cancels a running crawl instead of deleting it" do
    running = crawl_runs(:running_crawl)

    delete crawl_path(running), as: :json
    assert_response :success

    running.reload
    assert_equal "failed", running.status
    assert_match(/Cancelled by user/, running.error_message)
  end

  test "destroy deletes a finished crawl's record and its associated data" do
    finished = crawl_runs(:previous_completed)
    log_entry_ids = finished.crawl_log_entries.pluck(:id)
    unit_ids = finished.units.pluck(:id)
    assert unit_ids.any?, "fixture should have at least one unit to prove cascade delete"

    delete crawl_path(finished), as: :json
    assert_response :success

    assert_not CrawlRun.exists?(finished.id)
    assert_empty CrawlLogEntry.where(id: log_entry_ids)
    assert_empty Unit.where(id: unit_ids)
  end

  test "destroy_selected deletes only the finished crawls among the selected ids" do
    finished = crawl_runs(:previous_completed)
    running  = crawl_runs(:running_crawl)

    delete destroy_selected_crawls_path, params: { ids: [ finished.id, running.id ] }, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["deleted"]
    assert_equal 1, body["skipped"]

    assert_not CrawlRun.exists?(finished.id)
    assert CrawlRun.exists?(running.id)
  end

  test "destroy_selected with no ids returns an error instead of deleting anything" do
    count_before = CrawlRun.count

    delete destroy_selected_crawls_path, params: { ids: [] }, as: :json
    assert_response :unprocessable_content

    assert_equal count_before, CrawlRun.count
  end
end
