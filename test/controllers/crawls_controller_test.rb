# `require` loads test_helper.rb first, which sets up the Rails test
# environment (test database, fixtures, and auto-injected HTTP Basic Auth
# credentials for every simulated request in this suite).
require "test_helper"

# `class CrawlsControllerTest < ActionDispatch::IntegrationTest` defines this
# test class, inheriting request-simulation helpers (`get`/`post`/`patch`/
# `delete`) and assertion methods from Rails' integration test base class.
# These helpers send a request through the app's real router and controller
# code in-process, no actual browser or network socket involved.
class CrawlsControllerTest < ActionDispatch::IntegrationTest
  # `test "..." do ... end` is Minitest/Rails syntax defining one test case;
  # the string is the test's descriptive name, and the block is its body.
  test "create enqueues a crawl job and redirects" do
    # `CrawlRun.where(status: "running")` builds an ActiveRecord query for
    # every CrawlRun row whose `status` column equals "running" (fixture
    # data may include one, per test/fixtures/crawl_runs.yml). `.destroy_all`
    # deletes all matching rows immediately. This is done because the
    # controller's create action presumably checks "is a crawl already
    # running?" before starting a new one, clearing running rows here
    # guarantees that check passes, isolating this test from fixture state.
    # The trailing `#` comment documents why in the code itself.
    CrawlRun.where(status: "running").destroy_all # any_running? must be false

    # `assert_enqueued_with` is a Rails test helper (from ActiveJob::
    # TestHelper) that runs the block passed to it and then checks that a
    # background job matching the given options was scheduled ("enqueued")
    # during that block, WITHOUT actually running the job's code. `job:
    # CrawlJob` means "assert some instance of the CrawlJob class was
    # enqueued." This proves the controller kicks off background work
    # rather than, say, silently doing nothing.
    assert_enqueued_with(job: CrawlJob) do
      # `post` simulates an HTTP POST request (the verb for creating a new
      # resource / submitting a form). `params:` supplies the request's
      # parameters as a Ruby Hash, here flat (not nested under a model
      # name), mirroring simple form fields named `search_city` and
      # `radius_miles` directly. All values are given as strings since real
      # HTTP form submissions only ever send strings; the controller/model
      # converts types as needed.
      post crawls_path, params: { search_city: "Tempe, Arizona", radius_miles: "50" }
    end
    # `end` closes the `assert_enqueued_with(job: CrawlJob) do` block, only
    # the `post` call inside counts toward the enqueued-job check.

    # After a successful create, the controller redirects to the dashboard
    # (root) page rather than rendering anything itself.
    assert_redirected_to root_path
    # `CrawlRun.order(:created_at).last` sorts all CrawlRun rows by their
    # `created_at` timestamp ascending and takes the last (most recent) one
    #, i.e. "the crawl row that was just created by the request above."
    # `.search_city` reads its search_city column, confirming the value we
    # submitted was actually persisted correctly.
    assert_equal "Tempe, Arizona", CrawlRun.order(:created_at).last.search_city
  end
  # `end` closes the "create enqueues a crawl job and redirects" test block.

  test "create refuses to start a second crawl while one is already running" do
    # `CrawlRun.any_running?` is presumably a model class method (defined on
    # CrawlRun, not built into Rails) that returns true if any crawl has
    # status "running". `assert` with no comparison just checks the given
    # expression is truthy, here confirming the fixture data already has a
    # running crawl, which is the precondition this test needs.
    assert CrawlRun.any_running?

    # Attempts to start a second crawl anyway, while one is running.
    post crawls_path, params: { search_city: "Tempe, Arizona", radius_miles: "50" }

    # Even though the crawl is refused, the controller still redirects back
    # to the dashboard (rather than, say, returning an error status),
    # that's the existing Rails pattern of "always redirect after a POST,
    # explain the outcome via flash."
    assert_redirected_to root_path
    # Confirms the exact user-facing message shown when a second crawl is
    # blocked. `flash[:alert]` reads the one-time flash message stored under
    # the `:alert` key, set by the controller before redirecting.
    assert_equal "A crawl is already running. Please wait for it to finish before starting a new one.", flash[:alert]
  end
  # `end` closes the "create refuses to start a second crawl..." test block.

  test "create requires a search city" do
    # Clears any running crawl first so the "already running" guard from
    # the previous test doesn't interfere and hide the validation this test
    # actually wants to check.
    CrawlRun.where(status: "running").destroy_all

    # Submits an empty search_city to trigger the "you must enter a city"
    # validation path.
    post crawls_path, params: { search_city: "", radius_miles: "50" }

    assert_redirected_to root_path
    # `assert_match` checks that a string matches a Ruby Regexp (regular
    # expression), a pattern-matching tool for text. `/enter a city name/`
    # is regex literal syntax (slashes delimit the pattern); this one simply
    # looks for that literal phrase anywhere inside flash[:alert], which is
    # looser than assert_equal's exact-match check, useful when only part
    # of the message matters to the test.
    assert_match(/enter a city name/, flash[:alert])
  end
  # `end` closes the "create requires a search city" test block.

  test "create rejects an out-of-range radius" do
    CrawlRun.where(status: "running").destroy_all

    # Submits an absurdly large radius value to trigger a range-validation
    # failure.
    post crawls_path, params: { search_city: "Tempe, Arizona", radius_miles: "9999" }

    assert_redirected_to root_path
    # Same pattern-match style as above, checking the flash message
    # mentions the radius constraint without pinning down the exact wording.
    assert_match(/Radius must be between/, flash[:alert])
  end
  # `end` closes the "create rejects an out-of-range radius" test block.

  test "show renders the crawl's log entries" do
    # `crawl_runs(:previous_completed)` loads a fixture CrawlRun record
    # (defined in test/fixtures/crawl_runs.yml under the label
    # "previous_completed") and `crawl_path(...)` builds the URL for that
    # specific record's "show" page using its id.
    get crawl_path(crawl_runs(:previous_completed))
    assert_response :success
  end
  # `end` closes the "show renders the crawl's log entries" test block.

  test "show redirects with an alert when the crawl doesn't exist" do
    # An id far outside the range fixtures would ever generate, to force
    # the "record not found" branch.
    get crawl_path(id: 999_999)
    assert_redirected_to root_path
    assert_match(/not found/, flash[:alert])
  end
  # `end` closes the "show redirects with an alert..." test block.

  test "log returns JSON entries newer than since_id" do
    # Loads a fixture crawl and two fixture log entries to set up "one old
    # entry that already existed" versus "one new entry created during this
    # test," so the test can prove the endpoint filters correctly by id.
    crawl_run = crawl_runs(:previous_completed)
    older = crawl_log_entries(:info_entry)
    # `crawl_run.crawl_log_entries` is the ActiveRecord association of log
    # entries belonging to this crawl run (defined via `has_many` on the
    # CrawlRun model). `.create!` builds AND immediately saves a new
    # CrawlLogEntry row with the given attributes, associated with this
    # crawl_run automatically. The `!` (bang) means this raises an exception
    # if saving fails, rather than silently returning false, appropriate
    # in test setup, where a save failure should loudly break the test.
    newer = crawl_run.crawl_log_entries.create!(company: "system", level: "info", message: "newer entry")

    # `log_crawl_path(crawl_run)` builds the URL for this crawl's log
    # endpoint. `params: { since_id: older.id }` sends the older entry's id
    # as a query parameter, presumably telling the controller "only give me
    # entries newer than this one." `as: :json` is a keyword argument that
    # tells the test helper to set the request's Content-Type/Accept headers
    # to request/expect a JSON response, as an API client would, rather than
    # a full HTML page.
    get log_crawl_path(crawl_run), params: { since_id: older.id }, as: :json
    assert_response :success

    # `response.body` is the raw text of the HTTP response returned by the
    # request above (available on the implicit `response` object every
    # integration test gets after a request). `JSON.parse` converts that
    # JSON-formatted string into native Ruby data structures (Hashes/Arrays)
    # so the test can inspect it normally.
    body = JSON.parse(response.body)
    # `body["entries"]` reads the "entries" key from the parsed JSON hash.
    # `.map { |e| e["id"] }` transforms that array of entry hashes into a
    # plain array of just their "id" values, `.map` runs the block once per
    # element and collects the block's return values into a new array;
    # `|e|` names each element as `e` inside the block.
    ids = body["entries"].map { |e| e["id"] }
    # `assert_includes` checks that the `newer` entry's id IS present in the
    # returned list, proving new entries after since_id are included.
    assert_includes ids, newer.id
    # `refute_includes` is the negative counterpart, it checks the `older`
    # entry's id is NOT present, proving already-seen entries are correctly
    # excluded.
    refute_includes ids, older.id
  end
  # `end` closes the "log returns JSON entries newer than since_id" test.

  test "destroy cancels a running crawl instead of deleting it" do
    # Loads a fixture crawl that's currently "running," to exercise the
    # special-case behavior: cancelling instead of hard-deleting.
    running = crawl_runs(:running_crawl)

    # `delete` simulates an HTTP DELETE request (the verb for removing a
    # resource). `as: :json` again requests/expects a JSON response instead
    # of HTML.
    delete crawl_path(running), as: :json
    assert_response :success

    # `.reload` re-fetches this record's current data from the database,
    # since the `running` object in memory still holds its state from
    # BEFORE the delete request ran (that request happened in a separate,
    # already-finished simulated HTTP call, so this object wouldn't
    # otherwise reflect any changes the controller made to the underlying
    # row).
    running.reload
    # Confirms the record was NOT deleted but instead marked "failed",
    # proving "destroy" on a running crawl means "cancel it," not remove it.
    assert_equal "failed", running.status
    # Confirms the error_message column records that this was a
    # user-initiated cancellation, not a real crawl failure.
    assert_match(/Cancelled by user/, running.error_message)
  end
  # `end` closes the "destroy cancels a running crawl..." test block.

  test "destroy deletes a finished crawl's record and its associated data" do
    finished = crawl_runs(:previous_completed)
    # `.pluck(:id)` runs an efficient SQL query that returns just the `id`
    # column values (as a plain Ruby array) for every log entry belonging
    # to this crawl, without loading full ActiveRecord objects, used here
    # purely to remember which ids existed before deletion so we can check
    # they're gone afterward.
    log_entry_ids = finished.crawl_log_entries.pluck(:id)
    unit_ids = finished.units.pluck(:id)
    # Sanity-checks the fixture actually has at least one associated unit,
    # otherwise the cascade-delete assertions below (`assert_empty
    # Unit.where(...)`) would trivially pass even if cascading were broken,
    # since an empty set is empty either way. The string argument to
    # `assert` is a custom failure message shown if the assertion fails,
    # explaining why this particular check exists.
    assert unit_ids.any?, "fixture should have at least one unit to prove cascade delete"

    # Deletes a FINISHED (not running) crawl this time, different code
    # path than the cancel-instead-of-delete case above.
    delete crawl_path(finished), as: :json
    assert_response :success

    # `CrawlRun.exists?(finished.id)` returns true/false for whether a row
    # with that id still exists. `assert_not` asserts the given expression
    # is falsy, confirming the crawl run row itself was actually deleted.
    assert_not CrawlRun.exists?(finished.id)
    # `CrawlLogEntry.where(id: log_entry_ids)` builds a query matching any
    # of the previously-recorded ids. `assert_empty` checks the resulting
    # relation has zero records, confirming the crawl's log entries were
    # deleted too (a "cascade delete" via the model's associations), not
    # left orphaned in the database.
    assert_empty CrawlLogEntry.where(id: log_entry_ids)
    # Same cascade check for the crawl's associated storage units.
    assert_empty Unit.where(id: unit_ids)
  end
  # `end` closes the "destroy deletes a finished crawl's record..." test.

  test "destroy_selected deletes only the finished crawls among the selected ids" do
    finished = crawl_runs(:previous_completed)
    running  = crawl_runs(:running_crawl)

    # `destroy_selected_crawls_path` is a custom route (beyond the standard
    # RESTful ones) presumably for a bulk-delete-from-a-checklist feature.
    # `params: { ids: [ finished.id, running.id ] }` sends both a
    # deletable and a non-deletable id in one request, to prove the
    # controller filters rather than blindly deleting everything it's told
    # to. The array literal `[ ... ]` groups the two ids together as the
    # value for the `ids` param, matching how a browser would submit
    # multiple checked checkboxes under one parameter name.
    delete destroy_selected_crawls_path, params: { ids: [ finished.id, running.id ] }, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    # Confirms the JSON response reports exactly 1 deletion...
    assert_equal 1, body["deleted"]
    # ...and exactly 1 skip (the running crawl, which isn't safe to delete).
    assert_equal 1, body["skipped"]

    # Confirms the finished crawl really is gone from the database...
    assert_not CrawlRun.exists?(finished.id)
    # ...while the running crawl was left alone.
    assert CrawlRun.exists?(running.id)
  end
  # `end` closes the "destroy_selected deletes only the finished crawls..."
  # test block.

  test "destroy_selected with no ids returns an error instead of deleting anything" do
    # Records the row count beforehand so it can be compared after the
    # request, proving nothing changed.
    count_before = CrawlRun.count

    # Sends an empty array for `ids:`, an edge case where the user
    # submitted the bulk-delete form without checking anything.
    delete destroy_selected_crawls_path, params: { ids: [] }, as: :json
    # Expects a 422 error response (rather than :success) since there's
    # nothing valid to act on, this is the same "unprocessable content"
    # status used elsewhere in this app for rejected/invalid requests.
    assert_response :unprocessable_content

    # Confirms the crawl run count is completely unchanged.
    assert_equal count_before, CrawlRun.count
  end
  # `end` closes the "destroy_selected with no ids returns an error..." test.
end
# `end` closes the `class CrawlsControllerTest < ActionDispatch::IntegrationTest`
# definition that started at the top of the file.
