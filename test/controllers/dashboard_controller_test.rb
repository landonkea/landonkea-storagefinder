require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "index succeeds and shows the latest completed crawl's results" do
    get root_path
    assert_response :success
    assert_select "title", /Dashboard/
  end

  test "index succeeds when there has never been a completed crawl" do
    CrawlRun.destroy_all
    get root_path
    assert_response :success
  end

  test "index respects the history_keep_months setting for the history panel" do
    Setting.set("history_keep_months", "1")
    CrawlRun.create!(
      search_city: "Old City Outside Retention Window", search_radius_miles: 10, status: "completed",
      created_at: 3.months.ago
    )

    get root_path
    assert_response :success
    assert_no_match "Old City Outside Retention Window", response.body
  end

  test "status returns JSON with the running/latest crawl state" do
    get dashboard_status_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert body["crawl_running"]
    assert_equal crawl_runs(:running_crawl).id, body["running_crawl_id"]
    assert_equal crawl_runs(:current_completed).id, body["latest_crawl"]["id"]
  end

  test "results returns an empty payload when there's no crawl data yet" do
    CrawlRun.destroy_all
    get dashboard_results_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal [], body["units"]
  end

  test "results returns unit data for the latest completed crawl" do
    get dashboard_results_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert body["total"] > 0
    assert body["units"].any? { |u| u["company"] == "Public Storage" }
  end

  test "results sort param is sanitized against SQL injection" do
    get dashboard_results_path, params: { sort: "1; DROP TABLE units; --" }, as: :json
    assert_response :success
  end
end
