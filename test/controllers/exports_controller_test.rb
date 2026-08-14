# `require` loads test_helper.rb, setting up the Rails test environment
# (test database, fixtures, and auto-injected HTTP Basic Auth credentials
# for every simulated request below).
require "test_helper"

# `class ExportsControllerTest < ActionDispatch::IntegrationTest` declares
# this test class, inheriting Rails' request-simulation helpers (`get`,
# etc.) and assertion methods. These push a simulated request through the
# app's real routing/controller stack in-process, without a real browser or
# network socket.
class ExportsControllerTest < ActionDispatch::IntegrationTest
  # `test "..." do ... end` is Minitest/Rails syntax defining one test case;
  # the string names the test, the block holds its body.
  test "csv redirects with an alert when there's no crawl data" do
    # `CrawlRun.destroy_all` removes every crawl record (including
    # fixtures), simulating "nothing has ever been crawled" so the "no data
    # to export" branch of the controller can be exercised.
    CrawlRun.destroy_all

    # `get` simulates a browser GET request to the CSV export endpoint.
    get exports_csv_path
    # `assert_redirected_to` checks the response was an HTTP redirect (3xx)
    # AND that its target matches `root_path` (the dashboard), i.e.
    # instead of downloading a file, the user gets bounced back to the
    # dashboard because there's nothing to export.
    assert_redirected_to root_path
    # `flash[:alert]` reads the one-time flash message the controller set
    # before redirecting (flash messages survive exactly one subsequent
    # request, then clear). `assert_match` checks the message text contains
    # the given Regexp pattern, `/Run a crawl first/` is a regex literal
    # (delimited by slashes) matched loosely rather than requiring an exact
    # string match.
    assert_match(/Run a crawl first/, flash[:alert])
  end
  # `end` closes the "csv redirects with an alert when there's no crawl
  # data" test block.

  test "csv downloads a CSV file of the latest crawl's units" do
    # This time fixture data is left in place, so there IS a completed
    # crawl with units to export.
    get exports_csv_path
    assert_response :success
    # `response.media_type` reads just the MIME type portion of the
    # response's Content-Type header (e.g. "text/csv", without the
    # "charset=..." suffix Rails also sends). This assertion string-
    # concatenates ("+ ") a hardcoded "; charset=utf-8" suffix back onto it
    # before comparing, an odd way to write this check (see the flagged
    # issues at the end of this pass), but it does confirm the media type
    # itself is exactly "text/csv".
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    # `response.headers["Content-Disposition"]` reads the HTTP header
    # browsers use to decide whether to display a response inline or
    # prompt a file download. `assert_match(/attachment/, ...)` confirms
    # that header includes the word "attachment," which is what triggers a
    # download prompt rather than showing the CSV text in the browser.
    assert_match(/attachment/, response.headers["Content-Disposition"])
    # Confirms the actual CSV content includes real exported data, the
    # company name "Public Storage" from the fixture units, rather than
    # being empty or malformed. `response.body` is the raw text of the
    # response (here, the CSV file's contents).
    assert_match "Public Storage", response.body
  end
  # `end` closes the "csv downloads a CSV file of the latest crawl's units"
  # test block.

  test "excel redirects with an alert when there's no crawl data" do
    # Same "no data" setup as the CSV case above, but for the Excel export
    # endpoint.
    CrawlRun.destroy_all

    get exports_excel_path
    assert_redirected_to root_path
    assert_match(/Run a crawl first/, flash[:alert])
  end
  # `end` closes the "excel redirects with an alert when there's no crawl
  # data" test block.

  test "excel downloads an xlsx file of the latest crawl's units" do
    get exports_excel_path
    assert_response :success
    # Same download-header check as the CSV test, confirms the response
    # triggers a file download rather than rendering inline. Unlike the CSV
    # test, this doesn't assert on the file's binary content, since an
    # .xlsx file is a binary zip-based format, not readable/matchable as
    # plain text the way a CSV's text content is.
    assert_match(/attachment/, response.headers["Content-Disposition"])
  end
  # `end` closes the "excel downloads an xlsx file of the latest crawl's
  # units" test block.
end
# `end` closes the `class ExportsControllerTest < ActionDispatch::IntegrationTest`
# definition that started at the top of the file.
