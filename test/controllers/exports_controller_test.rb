require "test_helper"

class ExportsControllerTest < ActionDispatch::IntegrationTest
  test "csv redirects with an alert when there's no crawl data" do
    CrawlRun.destroy_all

    get exports_csv_path
    assert_redirected_to root_path
    assert_match(/Run a crawl first/, flash[:alert])
  end

  test "csv downloads a CSV file of the latest crawl's units" do
    get exports_csv_path
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match "Public Storage", response.body
  end

  test "excel redirects with an alert when there's no crawl data" do
    CrawlRun.destroy_all

    get exports_excel_path
    assert_redirected_to root_path
    assert_match(/Run a crawl first/, flash[:alert])
  end

  test "excel downloads an xlsx file of the latest crawl's units" do
    get exports_excel_path
    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])
  end
end
