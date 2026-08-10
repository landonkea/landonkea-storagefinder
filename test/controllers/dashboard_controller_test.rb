# `require` loads test_helper.rb, which sets up the Rails test environment
# (test database, fixtures, and auto-injected HTTP Basic Auth credentials
# for every request simulated below).
require "test_helper"

# `class DashboardControllerTest < ActionDispatch::IntegrationTest` declares
# this test class, inheriting Rails' request-simulation helpers (`get`,
# `post`, etc.) and assertion methods. These helpers push a request through
# the app's real routing/controller/view stack in-process, without a real
# browser or network socket.
class DashboardControllerTest < ActionDispatch::IntegrationTest
  # `test "..." do ... end` is Minitest/Rails syntax defining one test case;
  # the string names the test, the block is its body.
  test "index succeeds and shows the latest completed crawl's results" do
    # `get root_path` simulates a browser GET request to the app's home
    # page ("/"), which this app's DashboardController#index handles.
    get root_path
    # Checks the response status was in the 2xx ("success") range.
    assert_response :success
    # `assert_select` is a Rails test helper that parses the HTML response
    # body and checks for elements matching a CSS selector, here `"title"`
    # matches the page's `<title>` tag. The second argument, a Regexp
    # (`/Dashboard/`), is matched against that element's text content,
    # confirming the page title contains the word "Dashboard" somewhere.
    assert_select "title", /Dashboard/
  end
  # `end` closes the "index succeeds and shows the latest completed crawl's
  # results" test block.

  test "index succeeds when there has never been a completed crawl" do
    # `CrawlRun.destroy_all` deletes every CrawlRun row (including whatever
    # fixtures loaded), simulating a totally fresh install with no crawl
    # history, this test wants to prove the dashboard doesn't error out (a
    # common bug source: code that assumes "there's always at least one
    # record" and crashes on `nil`) when there's nothing to show yet.
    CrawlRun.destroy_all
    get root_path
    assert_response :success
  end
  # `end` closes the "index succeeds when there has never been a completed
  # crawl" test block.

  test "index respects the history_keep_months setting for the history panel" do
    # `Setting.set(key, value)` is presumably this app's own model method
    # for writing a key/value application setting into the database (as
    # opposed to a Rails config file), here configuring the dashboard's
    # history panel to only keep/show the last 1 month of crawl history.
    Setting.set("history_keep_months", "1")
    # `CrawlRun.create!` builds and immediately saves a new CrawlRun row.
    # The `!` (bang) means it raises an exception if saving fails rather
    # than silently returning false, which is desirable in test setup code.
    # Ruby lets you spread one method call's arguments across multiple
    # lines as long as the parentheses aren't closed early; the arguments
    # here are all named (keyword-style) attributes for the new record.
    CrawlRun.create!(
      # `search_city:` is deliberately named so its absence from the
      # dashboard's rendered HTML is unambiguous evidence of the
      # retention-window filter working, not a coincidence.
      search_city: "Old City Outside Retention Window", search_radius_miles: 10, status: "completed",
      # `3.months.ago` is ActiveSupport's date/time arithmetic: `3.months`
      # builds a duration object, and `.ago` subtracts it from the current
      # time, giving a Time object 3 months in the past. Setting
      # `created_at` explicitly (rather than letting Rails auto-set it to
      # "now") backdates this record outside the 1-month retention window
      # configured above.
      created_at: 3.months.ago
    )
    # `)` above closes the `CrawlRun.create!(` call opened several lines up.

    get root_path
    assert_response :success
    # `assert_no_match` is the negative counterpart to `assert_match`: it
    # checks the given string/pattern does NOT appear in `response.body`
    # (the raw HTML text of the page). Confirms the old, out-of-window
    # crawl's city name is correctly excluded from what's rendered.
    assert_no_match "Old City Outside Retention Window", response.body
  end
  # `end` closes the "index respects the history_keep_months setting..."
  # test block.

  test "status returns JSON with the running/latest crawl state" do
    # `as: :json` is a keyword argument telling the test helper to set
    # request headers (Content-Type/Accept) as a JSON API client would,
    # rather than requesting a full HTML page, appropriate here since this
    # endpoint is meant to be polled by JavaScript, not viewed directly.
    get dashboard_status_path, as: :json
    assert_response :success

    # `response.body` is the raw response text from the request above;
    # `JSON.parse` converts that JSON string into native Ruby Hashes/Arrays
    # so the test can inspect specific fields.
    body = JSON.parse(response.body)
    # `assert body["crawl_running"]` checks this value is truthy (Ruby
    # treats everything except `false` and `nil` as truthy), expecting the
    # JSON to report a crawl is currently running, matching fixture data.
    assert body["crawl_running"]
    # `crawl_runs(:running_crawl)` loads the fixture record labeled
    # "running_crawl" from test/fixtures/crawl_runs.yml; `.id` reads its
    # database id. Confirms the JSON correctly identifies WHICH crawl is
    # running, not just that one is.
    assert_equal crawl_runs(:running_crawl).id, body["running_crawl_id"]
    # Confirms the JSON's "latest_crawl" nested object correctly points at
    # the fixture labeled "current_completed", the most recent finished
    # crawl, distinct from the one still running.
    assert_equal crawl_runs(:current_completed).id, body["latest_crawl"]["id"]
  end
  # `end` closes the "status returns JSON with the running/latest crawl
  # state" test block.

  test "results returns an empty payload when there's no crawl data yet" do
    # Wipes all crawl data to simulate a fresh install with nothing to show.
    CrawlRun.destroy_all
    get dashboard_results_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    # Confirms the JSON's "units" field is an empty array `[]` (Ruby array
    # literal syntax) rather than `nil` or an error, an API contract worth
    # locking down, since client-side JS likely expects to always be able
    # to call array methods on this field without a nil-check.
    assert_equal [], body["units"]
  end
  # `end` closes the "results returns an empty payload..." test block.

  test "results returns unit data for the latest completed crawl" do
    get dashboard_results_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    # Checks the "total" count reported in the JSON is greater than zero,
    # relying on whatever units the default fixtures provide, rather than
    # pinning an exact number (which would make this test brittle to
    # unrelated fixture changes).
    assert body["total"] > 0
    # `body["units"].any? { |u| ... }` runs the block once per element in
    # the "units" array and returns true if the block returns truthy for AT
    # LEAST one of them (`|u|` names each unit hash inside the block).
    # Confirms a specific real company name ("Public Storage") shows up
    # somewhere in the results, proving actual scraped data flows through,
    # not just placeholder/empty records.
    assert body["units"].any? { |u| u["company"] == "Public Storage" }
  end
  # `end` closes the "results returns unit data for the latest completed
  # crawl" test block.

  test "results sort param is sanitized against SQL injection" do
    # Deliberately sends a malicious-looking value for the `sort` param,
    # text that would be a SQL injection attack if it were dropped
    # unsanitized into a raw SQL "ORDER BY" clause. This test doesn't check
    # the sort actually applied correctly; it only checks the request
    # doesn't error out (e.g. by raising a SQL syntax error or, worse,
    # actually executing the injected SQL), a minimal but important
    # security regression check.
    get dashboard_results_path, params: { sort: "1; DROP TABLE units; --" }, as: :json
    assert_response :success
  end
  # `end` closes the "results sort param is sanitized against SQL injection"
  # test block.

  test "index shows a warning/error badge count on crawl history rows that have log issues" do
    # test/fixtures/crawl_log_entries.yml's "error_entry" fixture belongs to
    # crawl_run_id 1 (crawl_runs(:previous_completed), pinned to that exact
    # id), this asserts DashboardController#index's @crawl_log_counts
    # query surfaces that single error entry as a rendered "⚠ 1" badge
    # rather than silently dropping it.
    get root_path
    assert_response :success
    assert_match "⚠ 1", response.body
  end
  # `end` closes the "index shows a warning/error badge count..." test block.

  test "index shows no issue badge for a crawl with no warning/error log entries" do
    # crawl_runs(:current_completed) (id 2) has no crawl_log_entries fixture
    # rows at all, its history row should render the plain "—" placeholder
    # instead of any badge.
    get root_path
    assert_response :success
    assert_match "—", response.body
  end
  # `end` closes the "index shows no issue badge..." test block.

  test "index disables the StorAmerica company checkbox and marks it unsupported" do
    # StorAmerica's parser (app/services/companies/stor_america.rb) is a
    # stub, it always returns zero results. CompanyRegistry.stubbed?
    # drives the dashboard's checkbox rendering (see
    # app/views/dashboard/index.html.erb) to disable it and label it
    # clearly, instead of silently letting it be selected.
    #
    # The company checkboxes only render on the "start a new crawl" form,
    # which the dashboard hides while a crawl is already running (see
    # `if @crawl_running && @running_crawl` in index.html.erb),
    # test/fixtures/crawl_runs.yml's "running_crawl" fixture is active by
    # default, so it's reset to "completed" here first.
    CrawlRun.where(status: "running").update_all(status: "completed")

    get root_path
    assert_response :success

    # `assert_select` parses the response HTML and finds elements matching
    # a CSS selector, this locates the specific checkbox whose value is
    # "StorAmerica" and asserts it carries the `disabled` attribute.
    assert_select "input[name='companies[]'][value='StorAmerica'][disabled]"
    assert_match "(not yet supported)", response.body
  end
  # `end` closes the "index disables the StorAmerica company checkbox..."
  # test block.
end
# `end` closes the `class DashboardControllerTest < ActionDispatch::IntegrationTest`
# definition that started at the top of the file.
