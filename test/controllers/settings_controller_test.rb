# `require` loads test_helper.rb, setting up the Rails test environment
# (test database, fixtures, auto-injected HTTP Basic Auth credentials, and
# the `stub_any_instance` helper used near the bottom of this file).
require "test_helper"

# `class SettingsControllerTest < ActionDispatch::IntegrationTest` declares
# this test class, inheriting Rails' request-simulation helpers (`get`,
# `post`, `patch`, etc.) and assertion methods. These push a simulated
# request through the app's real routing/controller stack in-process,
# without a real browser or network socket.
class SettingsControllerTest < ActionDispatch::IntegrationTest
  # `test "..." do ... end` is Minitest/Rails syntax defining one test case;
  # the string names the test, the block holds its body.
  test "index succeeds" do
    # `get` simulates a browser GET request to the settings page.
    get settings_path
    # Checks the response status was in the 2xx ("success") range.
    assert_response :success
  end
  # `end` closes the "index succeeds" test block.

  test "update saves a text setting" do
    # `patch` simulates an HTTP PATCH request, the verb conventionally used
    # for partial updates to an existing resource. `params:` supplies the
    # request's parameters as a Ruby Hash, here nested under a `settings:`
    # key holding a hash of individual setting names to their new values
    # (mirroring how a settings form would submit many fields named like
    # `settings[email_smtp_host]` at once). String keys like
    # "email_smtp_host" are used (rather than symbols) because that's how
    # real HTTP form field names arrive.
    patch settings_path, params: { settings: { "email_smtp_host" => "smtp.new-host.com" } }
    # `assert_redirected_to` checks the response was an HTTP redirect (3xx)
    # back to the settings page itself, the standard "save, then redirect
    # to avoid re-submitting on refresh" pattern.
    assert_redirected_to settings_path
    # `Setting.get(key)` is presumably this app's own model method for
    # reading back a stored key/value application setting. Confirms the
    # new value was actually persisted, not just accepted and discarded.
    assert_equal "smtp.new-host.com", Setting.get("email_smtp_host")
  end
  # `end` closes the "update saves a text setting" test block.

  test "update ignores unknown setting keys (form tampering protection)" do
    # Submits a key that isn't one of the app's real, expected settings,
    # simulating a malicious or malformed request (e.g. someone editing the
    # form's HTML in devtools to add an extra field) rather than a normal
    # user interaction.
    patch settings_path, params: { settings: { "not_a_real_setting" => "value" } }
    # The controller should still redirect normally rather than erroring...
    assert_redirected_to settings_path
    # ...but `Setting.find_by(key: "not_a_real_setting")`, an ActiveRecord
    # lookup that returns the matching record or `nil` if none exists,
    # should come back nil, confirming the controller only ever writes
    # settings from an allow-list of known keys instead of blindly saving
    # whatever params arrive.
    assert_nil Setting.find_by(key: "not_a_real_setting")
  end
  # `end` closes the "update ignores unknown setting keys..." test block.

  test "update treats a checked boolean checkbox as true" do
    # HTML checkboxes are tricky to submit correctly: a checked checkbox
    # sends its "on" value, but an UNCHECKED checkbox sends nothing at all
    # unless a hidden field is added alongside it. Rails' standard
    # `check_box` form helper handles this by rendering a hidden field with
    # the SAME name ending in "_unchecked" that always submits "false" as a
    # fallback, so the checked value ("true", sent by the visible checkbox)
    # can override it when present. This test simulates a browser
    # submitting BOTH fields, as a real checked checkbox's form actually
    # would, to prove the controller correctly ends up with `true` when
    # both are present.
    patch settings_path, params: {
      settings: { "crawl_headless" => "true", "crawl_headless_unchecked" => "false" }
    }
    # `assert_equal true, ...` checks the stored value is the actual Ruby
    # boolean `true` (not the string `"true"`), confirming the controller
    # converts/casts the submitted text into a real boolean before saving.
    assert_equal true, Setting.get("crawl_headless")
  end
  # `end` closes the "update treats a checked boolean checkbox as true"
  # test block.

  test "update treats an unchecked boolean checkbox as false" do
    # Pre-sets the setting to "true" so this test can prove the update
    # actually flips it to false, rather than the assertion below trivially
    # passing because the value was already false.
    Setting.set("crawl_headless", "true")

    # Simulates an UNCHECKED checkbox: only the "_unchecked" hidden fallback
    # field is submitted ("crawl_headless" itself is absent, exactly as a
    # real browser would omit it for an unchecked box).
    patch settings_path, params: {
      settings: { "crawl_headless_unchecked" => "false" }
    }
    # Confirms the setting ends up as boolean `false`, proving the
    # controller correctly falls back to the "_unchecked" field's value
    # when the main checkbox field is missing.
    assert_equal false, Setting.get("crawl_headless")
  end
  # `end` closes the "update treats an unchecked boolean checkbox as false"
  # test block.

  test "update skips a blank password field instead of wiping out the stored value" do
    # Pre-sets a password value to prove it survives the update below.
    Setting.set("email_smtp_password", "super-secret")

    # Submits an empty string for the password field, simulating a user
    # who opens the settings form (which presumably shows password fields
    # blank for security, not pre-filled with the real secret) and saves
    # without intending to change the password.
    patch settings_path, params: { settings: { "email_smtp_password" => "" } }

    # Confirms the ORIGINAL password is still stored, the controller must
    # specifically special-case blank password fields as "leave unchanged"
    # rather than treating them like any other field (which would wipe the
    # stored secret out to an empty string).
    assert_equal "super-secret", Setting.get("email_smtp_password")
  end
  # `end` closes the "update skips a blank password field..." test block.

  test "update saves a non-blank password field" do
    # The counterpart to the previous test: proves that submitting an
    # ACTUAL new password value (not blank) does correctly overwrite the
    # stored one, i.e. the blank-field special case above doesn't
    # accidentally block real password changes too.
    patch settings_path, params: { settings: { "email_smtp_password" => "new-secret" } }
    assert_equal "new-secret", Setting.get("email_smtp_password")
  end
  # `end` closes the "update saves a non-blank password field" test block.

  test "test_email fails cleanly when no recipient is configured" do
    # Explicitly clears the configured recipient email address, so the
    # "send a test email" feature has nothing valid to send to.
    Setting.set("email_to_address", "")

    # `post` simulates an HTTP POST request to trigger the "send test
    # email" action. `as: :json` tells the test helper to set request
    # headers as a JSON API client would (this endpoint is presumably
    # called via JavaScript from the settings page, returning a JSON
    # success/failure payload rather than a full HTML page or redirect).
    post test_email_settings_path, as: :json
    # Even though the underlying action "failed" (no recipient), the HTTP
    # response itself is still a successful 2xx, the failure is reported
    # INSIDE the JSON body, not via the HTTP status code. This is a common
    # API pattern: "the request was handled correctly, and here's the
    # business-logic outcome," as opposed to using HTTP error codes for
    # every kind of failure.
    assert_response :success

    # `JSON.parse(response.body)` converts the raw JSON response text into
    # a Ruby Hash so individual fields can be checked.
    body = JSON.parse(response.body)
    # `refute` is Minitest's assertion that the given expression is falsy
    # (the opposite of `assert`). Confirms the JSON's "success" field is
    # false/falsy, reporting the operation did not succeed.
    refute body["success"]
    # Confirms the human-readable failure message explains WHY, no
    # recipient was configured, via a loose Regexp match rather than an
    # exact string match.
    assert_match(/No recipient/, body["message"])
  end
  # `end` closes the "test_email fails cleanly when no recipient is
  # configured" test block.

  test "test_discord fails cleanly when no webhook is configured" do
    # Same pattern as the email test above, but for Discord notifications:
    # clears the webhook URL setting so there's nowhere to send a test
    # message.
    Setting.set("discord_webhook_url", "")

    post test_discord_settings_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    refute body["success"]
    assert_match(/No Discord webhook/, body["message"])
  end
  # `end` closes the "test_discord fails cleanly when no webhook is
  # configured" test block.

  test "test_discord reports a connection failure without raising" do
    # This time a (fake-looking but well-formed) webhook URL IS configured,
    # so the code will actually attempt to make an outbound HTTP call to
    # it, which this test needs to intercept rather than really hitting
    # the network.
    Setting.set("discord_webhook_url", "https://discord.com/api/webhooks/x/y")

    # `stub_any_instance` is a custom helper defined in test_helper.rb (not
    # built into Rails/Minitest) that temporarily replaces a method on
    # EVERY instance of a class for the duration of the block passed to it,
    # then restores the original afterward. Here it replaces
    # `Faraday::Connection#post` (Faraday is the HTTP client library this
    # app uses to call the Discord webhook) so that calling it doesn't make
    # a real network request, instead it always raises a
    # `Faraday::ConnectionFailed` error, simulating "the network call
    # failed" (e.g. DNS failure, connection refused) deterministically and
    # without needing real network access in tests. `->(*) { ... }` is a
    # Ruby lambda (an anonymous function), `(*)` accepts any number of
    # arguments without needing to name them individually, since this fake
    # implementation doesn't care what arguments the real `post` call would
    # have received.
    stub_any_instance(Faraday::Connection, :post, ->(*) { raise Faraday::ConnectionFailed, "connection refused" }) do
      # The actual request under test, made while the stub above is
      # active, any Faraday::Connection#post call triggered inside the
      # controller during this request will hit the fake, raising
      # implementation instead of a real HTTP call.
      post test_discord_settings_path, as: :json
    end
    # `end` closes the `stub_any_instance(...) do` block, once execution
    # passes this point, Faraday::Connection#post is back to its real
    # implementation (handled by the `ensure` in test_helper.rb's
    # stub_any_instance definition).

    # Even though the underlying network call blew up, the controller
    # should have RESCUED that error and returned a normal, successful HTTP
    # response reporting the failure in the JSON body, proving the
    # controller doesn't let a downstream network error crash the whole
    # request (which would surface as a 500 Internal Server Error instead).
    assert_response :success
    body = JSON.parse(response.body)
    refute body["success"]
    assert_match(/Could not connect/, body["message"])
  end
  # `end` closes the "test_discord reports a connection failure without
  # raising" test block.
end
# `end` closes the `class SettingsControllerTest < ActionDispatch::IntegrationTest`
# definition that started at the top of the file.
