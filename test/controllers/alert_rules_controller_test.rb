# `require` pulls in another file's code before this file runs. Ruby needs
# this "test_helper.rb" file loaded first because it sets up the whole Rails
# test environment (database connection, fixtures, HTTP Basic Auth
# credentials injected into every request, etc.) that every test below
# depends on.
require "test_helper"

# `class ... < ActionDispatch::IntegrationTest` defines a new Ruby class
# named AlertRulesControllerTest that inherits ("< ") from Rails'
# ActionDispatch::IntegrationTest. Inheriting from this base class is what
# gives this class all its testing powers: the `test` method below, HTTP
# request helpers like `get`/`post`/`patch`/`delete` that simulate a real
# browser making a request to the app WITHOUT actually starting a browser or
# a real server, and assertion methods like `assert_response` for checking
# what came back. This is Rails' way of testing controllers end-to-end,
# through the same routing/controller/view pipeline a real user would hit.
class AlertRulesControllerTest < ActionDispatch::IntegrationTest
  # `test "..." do ... end` is a Minitest/Rails helper (not raw Ruby syntax)
  # that defines one individual test case. Under the hood it turns the
  # string into a method name (like `test_index_lists_alert_rules`) and
  # defines that method with the given block as its body. Each `test` block
  # runs independently, in a fresh database transaction that's rolled back
  # afterward, so tests can't leak state into each other.
  test "index lists alert rules" do
    # `get` simulates a browser sending an HTTP GET request to the given
    # path — no real network call happens, Rails just runs the request
    # straight through its router and controller code in-process. Note:
    # test_helper.rb overrides this `get` method for the whole test suite so
    # it automatically attaches valid HTTP Basic Auth credentials to every
    # request (this app requires them); that happens invisibly here.
    # `alert_rules_path` is a route helper Rails auto-generates from
    # `config/routes.rb` — it returns the URL string for the alert rules
    # index page (e.g. "/alert_rules") without hardcoding it.
    get alert_rules_path
    # `assert_response :success` checks that the HTTP response status code
    # was in the 2xx range (200 OK, etc.) — i.e. the request didn't error
    # out or redirect. `:success` is a Ruby Symbol, a lightweight named
    # constant often used (as here) as a label/enum value rather than
    # holding arbitrary data like a string would.
    assert_response :success
  end
  # `end` closes the `test "index lists alert rules" do` block above.

  test "show renders a single rule" do
    # `alert_rule_path(...)` builds the URL for one specific alert rule's
    # "show" page, e.g. "/alert_rules/5". `alert_rules(:price_drop_rule)`
    # looks up a test fixture: a pre-defined database row loaded from
    # test/fixtures/alert_rules.yml under the label "price_drop_rule",
    # giving back the real AlertRule record so its `id` can be used to build
    # the URL.
    get alert_rule_path(alert_rules(:price_drop_rule))
    # Checks the page rendered successfully (2xx status).
    assert_response :success
  end
  # `end` closes the `test "show renders a single rule" do` block above.

  test "show redirects with an alert when the rule doesn't exist" do
    # Requests a rule id that can't exist in the test database (fixtures use
    # much smaller auto-generated ids), to exercise the "not found" branch
    # of the controller's `show` action.
    get alert_rule_path(id: 999_999)
    # `assert_redirected_to` checks two things at once: that the response
    # was an HTTP redirect (3xx status), AND that the redirect's target URL
    # matches the given path. `alert_rules_path` here is the index page —
    # i.e. we expect to be bounced back to the list instead of shown a
    # missing record.
    assert_redirected_to alert_rules_path
    # `flash` is Rails' mechanism for passing a one-time message across a
    # redirect (it survives exactly one subsequent request, then clears
    # itself) — commonly used for messages like "Item not found" or "Saved
    # successfully" shown after the browser follows the redirect.
    # `flash[:alert]` reads the message stored under the `:alert` key, and
    # `assert_equal` checks it exactly matches the given string.
    assert_equal "Alert rule not found.", flash[:alert]
  end
  # `end` closes the "show redirects..." test block above.

  test "new renders the form" do
    # Requests the "new alert rule" form page (an empty form for creating
    # one), rather than a form pre-filled for an existing record.
    get new_alert_rule_path
    assert_response :success
  end
  # `end` closes the "new renders the form" test block above.

  test "create saves a valid rule and redirects" do
    # `assert_difference` runs the block passed to it, then checks that the
    # given expression's value changed by exactly the given amount between
    # before and after. Here it evaluates "AlertRule.count" (as a string,
    # which Rails evaluates in the test's context) both before and after the
    # block runs, and asserts it went up by exactly 1 — proving the create
    # action actually persisted a new row rather than, say, silently failing
    # validation.
    assert_difference "AlertRule.count", 1 do
      # `post` simulates an HTTP POST request — the verb browsers use when
      # submitting a form to create something new (as opposed to `get`,
      # which only fetches/reads data and shouldn't have side effects).
      # `params:` is a keyword argument that supplies the request's
      # parameters, exactly like form fields or query-string values a real
      # browser would send. Here it's a nested hash: the outer key
      # `alert_rule:` groups the fields the controller expects for the
      # `alert_rule` param (mirroring how Rails form builders name inputs
      # like `alert_rule[name]`), and the inner hash holds the actual field
      # values (all passed as strings, since real HTTP form fields are
      # always strings — the controller/model layer is responsible for
      # converting types like `threshold_price` to a number).
      post alert_rules_path, params: {
        alert_rule: {
          name: "New rule", trigger_type: "price_threshold", threshold_price: "50",
          email_enabled: "true", email_address: "x@example.com"
        }
      }
    end
    # `end` closes the `assert_difference "AlertRule.count", 1 do` block —
    # everything above between `do` and here is what gets measured for the
    # count change.

    # After a successful create, the controller should redirect back to the
    # index page (the standard Rails "create, then redirect" pattern, which
    # avoids re-submitting the form if the user refreshes the page).
    assert_redirected_to alert_rules_path
  end
  # `end` closes the "create saves a valid rule..." test block above.

  test "create re-renders the form with errors for an invalid rule" do
    # `assert_no_difference` is the opposite of `assert_difference` above:
    # it asserts the given expression's value is UNCHANGED after the block
    # runs — here, proving that an invalid submission does NOT create a new
    # database row.
    assert_no_difference "AlertRule.count" do
      # Submits a rule with a blank `name` (invalid, since the model
      # presumably validates it's required) to trigger the failure path.
      post alert_rules_path, params: {
        alert_rule: { name: "", trigger_type: "price_threshold", threshold_price: "50" }
      }
    end
    # `end` closes the `assert_no_difference "AlertRule.count" do` block.

    # HTTP 422 ("Unprocessable Content/Entity") is the conventional status
    # Rails uses when re-rendering a form because validation failed — as
    # opposed to :success (200), which would mean it saved, or a redirect,
    # which would mean it moved on to another page.
    assert_response :unprocessable_content
  end
  # `end` closes the "create re-renders the form with errors..." test block.

  test "edit renders the form" do
    # Requests the edit form for an existing fixture record, pre-filled
    # with that record's current values (as opposed to `new`, which is
    # blank).
    get edit_alert_rule_path(alert_rules(:price_drop_rule))
    assert_response :success
  end
  # `end` closes the "edit renders the form" test block above.

  test "update saves changes and redirects" do
    # Grabs the fixture record and stores it in a local variable so it can
    # be referenced both to build the URL below and to re-check its state
    # after the update.
    rule = alert_rules(:price_drop_rule)

    # `patch` simulates an HTTP PATCH request — the verb conventionally used
    # for partial updates to an existing resource (as opposed to `post` for
    # creating something new). Only the `name` field is sent, so this
    # exercises updating just one attribute while leaving the rest alone.
    patch alert_rule_path(rule), params: { alert_rule: { name: "Renamed rule" } }

    # Successful updates redirect back to the index, same pattern as create.
    assert_redirected_to alert_rules_path
    # `rule.reload` re-fetches this record's data fresh from the database
    # (the in-memory `rule` object wouldn't otherwise know about changes the
    # controller action made in a separate, already-finished request), then
    # `.name` reads its `name` column so we can confirm the update actually
    # persisted rather than just returning a redirect without saving.
    assert_equal "Renamed rule", rule.reload.name
  end
  # `end` closes the "update saves changes and redirects" test block above.

  test "update re-renders the form with errors for invalid changes" do
    rule = alert_rules(:price_drop_rule)

    # Sends a combination of fields that presumably fails a model
    # validation (e.g. "at least one notification channel must be enabled")
    # by turning every notification channel off at once.
    patch alert_rule_path(rule), params: {
      alert_rule: { email_enabled: "false", discord_enabled: "false", sms_enabled: "false" }
    }

    # Same 422 status as the invalid-create case above: the form is
    # re-rendered with validation errors instead of redirecting.
    assert_response :unprocessable_content
  end
  # `end` closes the "update re-renders the form with errors..." test block.

  test "destroy deletes the rule and redirects" do
    rule = alert_rules(:price_drop_rule)

    # Measures that AlertRule.count goes DOWN by 1 (note the `-1`, unlike
    # the `1` used for create above) as a result of the delete request
    # inside this block.
    assert_difference "AlertRule.count", -1 do
      # `delete` simulates an HTTP DELETE request — the verb conventionally
      # used to destroy a resource.
      delete alert_rule_path(rule)
    end
    # `end` closes the `assert_difference "AlertRule.count", -1 do` block.

    # After deleting, the controller redirects back to the index page.
    assert_redirected_to alert_rules_path
  end
  # `end` closes the "destroy deletes the rule and redirects" test block.

  test "destroy_selected deletes every given id and redirects" do
    ids = [ alert_rules(:price_drop_rule).id, alert_rules(:inactive_rule).id ]

    assert_difference "AlertRule.count", -2 do
      delete destroy_selected_alert_rules_path, params: { ids: ids }
    end

    assert_redirected_to alert_rules_path
    assert_equal "Deleted 2 alert rules.", flash[:notice]
  end
  # `end` closes the "destroy_selected deletes every given id..." test block.

  test "destroy_selected leaves everything alone when no ids are given" do
    assert_no_difference "AlertRule.count" do
      delete destroy_selected_alert_rules_path
    end

    assert_redirected_to alert_rules_path
    assert_equal "No alert rules were selected.", flash[:alert]
  end
  # `end` closes the "destroy_selected leaves everything alone..." test block.
end
# `end` closes the `class AlertRulesControllerTest < ActionDispatch::IntegrationTest`
# definition that started at the top of the file.
