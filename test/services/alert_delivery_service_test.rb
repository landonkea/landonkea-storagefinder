# `require "test_helper"` loads test/test_helper.rb, which boots Rails in
# test mode and defines the `stub_any_instance` helper used repeatedly
# below to fake out real network calls to Discord.
require "test_helper"

# This file tests AlertDeliveryService (app/services/alerting/alert_delivery_service.rb)
#, the class responsible for actually sending an alert notification via
# email and/or Discord, once AlertMessageBuilder has built the message
# content and AlertCheckerJob has decided a rule fired.
class AlertDeliveryServiceTest < ActiveSupport::TestCase
  # `def alert_message` defines a small helper METHOD (not a `test "..."`
  # block) available to every test in this class. It returns a Hash with
  # the same shape AlertMessageBuilder.build produces (see
  # app/services/alerting/alert_message_builder.rb), a stand-in message so
  # these tests don't need to build a real one via AlertMessageBuilder just
  # to exercise AlertDeliveryService's delivery logic.
  def alert_message
    { subject: "Test", text_body: "body", html_body: "<p>body</p>", sms_body: "sms" }
  end
  # `end` closes the `def alert_message` helper method definition above.

  test "deliver skips email when globally disabled, even if the rule has it enabled" do
    # `Setting.set("email_enabled", "false")` writes to the Setting model's
    # key-value store (see app/models/setting.rb), this is the GLOBAL,
    # app-wide toggle for whether email alerts are allowed at all,
    # independent of any individual alert rule's own settings.
    Setting.set("email_enabled", "false")
    # `alert_rules(:price_drop_rule)` looks up the AlertRule fixture named
    # "price_drop_rule" (test/fixtures/alert_rules.yml), which, per the
    # inline comment kept from the original test, has its OWN
    # `email_enabled` column set to true. This test proves the global
    # Setting still wins over the rule's own flag.
    rule = alert_rules(:price_drop_rule) # email_enabled: true on the rule itself

    # No SMTP settings configured either, so a real attempt would raise,
    # if this doesn't raise, the global disable short-circuited it.
    # `AlertDeliveryService.deliver(rule, alert_message)` calls the class
    # method (see app/services/alerting/alert_delivery_service.rb) that
    # builds a new AlertDeliveryService instance and runs `.deliver` on it.
    # If email delivery had NOT been correctly skipped, this call would
    # attempt a real SMTP connection with blank credentials and raise,
    # since nothing here rescues an exception, the test itself would fail
    # with an error if that happened.
    AlertDeliveryService.deliver(rule, alert_message)
    # `assert true` is a trivial "this test passed" marker, it exists
    # because the real assertion in this test is "no exception was raised
    # above," which Minitest already reports as a failure on its own if it
    # happens; this call just gives the test an explicit passing assertion
    # to satisfy the convention that every test makes at least one.
    assert true
  end
  # `end` closes the "deliver skips email when globally disabled..." test block above.

  test "deliver skips discord when the rule doesn't have it enabled, even if globally enabled" do
    Setting.set("discord_enabled", "true")
    rule = alert_rules(:price_drop_rule) # discord_enabled: false on the rule

    # `stub_any_instance(Faraday::Connection, :post, ->(*) { raise "..." })
    # do ... end`, from test_helper.rb, temporarily replaces the `post`
    # method on EVERY instance of Faraday::Connection (the HTTP client
    # class AlertDeliveryService uses to talk to Discord's webhook API)
    # with a fake implementation that always raises an error. `->(*) { ... }`
    # is a lambda accepting any arguments (`*` "splat" = "ignore them all").
    # If AlertDeliveryService's code path for this test ever actually tried
    # to POST to Discord, this fake would raise and fail the test loudly,
    # proving instead that it correctly skipped Discord delivery entirely
    # (because the rule itself has discord_enabled: false), never even
    # calling .post.
    stub_any_instance(Faraday::Connection, :post, ->(*) { raise "should not have posted to Discord" }) do
      AlertDeliveryService.deliver(rule, alert_message)
    end
    # `end` closes the `stub_any_instance(...) do ... end` block above.
    assert true
  end
  # `end` closes the "deliver skips discord when the rule doesn't have it
  # enabled..." test block above.

  test "deliver_email logs and returns early when SMTP settings are incomplete" do
    Setting.set("email_enabled", "true")
    # Setting the SMTP username to an empty string (rather than leaving it
    # unset) exercises the ".blank?" check inside deliver_email (see
    # app/services/alerting/alert_delivery_service.rb), Rails' `.blank?`
    # treats both nil AND an empty/whitespace-only string as "blank," so
    # this triggers the same "incomplete SMTP settings" early-return path.
    Setting.set("email_smtp_username", "")
    rule = alert_rules(:price_drop_rule)

    AlertDeliveryService.deliver(rule, alert_message) # would raise if it tried a real SMTP connection
    assert true
  end
  # `end` closes the "deliver_email logs and returns early..." test block above.

  test "deliver_discord logs and returns early when no webhook URL is configured" do
    Setting.set("discord_enabled", "true")
    # Setting the global webhook URL to an empty string means there's no
    # fallback URL either, combined with price_threshold_rule not having
    # its own discord_webhook_url set (per the comment below), there is NO
    # URL available anywhere, which should make deliver_discord bail out
    # early rather than attempting a POST to a blank/invalid URL.
    Setting.set("discord_webhook_url", "")
    rule = alert_rules(:price_threshold_rule) # discord_enabled: true, but no rule-specific webhook either

    AlertDeliveryService.deliver(rule, alert_message)
    assert true
  end
  # `end` closes the "deliver_discord logs and returns early..." test block above.

  test "deliver_discord posts to the rule's webhook URL when set, over the global default" do
    Setting.set("discord_enabled", "true")
    Setting.set("discord_webhook_url", "https://discord.com/api/webhooks/global/default")
    rule = alert_rules(:price_threshold_rule)
    # `rule.update!(discord_webhook_url: "...")` sets a webhook URL directly
    # on this ONE rule, which, per AlertDeliveryService's logic, should
    # take priority over the global default Setting configured above.
    rule.update!(discord_webhook_url: "https://discord.com/api/webhooks/rule/specific")

    # `posted_to = nil` declares a local variable, initialized to nil, that
    # the fake `.post` implementation below will fill in, this is how the
    # test "captures" a value from inside the stub to check afterward,
    # since the stub's lambda runs in a different context (as a method body
    # on Faraday::Connection) but can still read/write variables from the
    # surrounding Ruby scope thanks to how Ruby blocks/lambdas form
    # closures (they remember the local variables of the code that created
    # them).
    posted_to = nil
    # `Struct.new(:success?, :status, :body).new(true, 200, "ok")` builds a
    # lightweight fake HTTP response object. `Struct.new(...)` dynamically
    # generates a brand-new, unnamed Ruby class with three reader methods,
    # `success?`, `status`, and `body`, then `.new(true, 200, "ok")`
    # immediately instantiates ONE object of that class, with `success?`
    # returning `true`, `status` returning `200`, and `body` returning
    # `"ok"`. This mimics the shape of a real Faraday response object well
    # enough for AlertDeliveryService's `response.success?` /
    # `response.status` / `response.body` calls to work without needing an
    # actual HTTP library response.
    fake_response = Struct.new(:success?, :status, :body).new(true, 200, "ok")

    # Faraday::Connection's url_prefix reflects the URL Faraday.new(url) was
    # called with, so reading it from inside the stub (where `self` is the
    # Connection instance) confirms which webhook URL was actually used.
    # `stub_any_instance(Faraday::Connection, :post, ->(&blk) { ... }) do
    # ... end` fakes `.post` on every Faraday::Connection instance again,
    # but this time the fake implementation itself takes a block parameter
    # `&blk`, because the real code calls `.post do |req| ... end`
    # (see deliver_discord in alert_delivery_service.rb), and this fake
    # needs to accept and actually run that block for the surrounding code
    # to behave realistically.
    stub_any_instance(Faraday::Connection, :post, ->(&blk) {
      # Builds another fake object, this time standing in for the
      # "request" object (`req`) that the real Faraday .post block would
      # normally receive, with fake `headers` (an empty Hash) and `body`
      # (nil) fields that the block can read/write.
      req = Struct.new(:headers, :body).new({}, nil)
      # `blk.call(req) if blk` runs the block that was passed to `.post`
      # (the real code's `do |req| ... end`), handing it this fake request
      # object, `if blk` guards against calling nothing if no block was
      # given at all. This lets the real code's header-setting/body-setting
      # logic actually execute against the fake `req`, just like it would
      # against a real one.
      blk.call(req) if blk
      # Because this whole lambda is being run AS an instance method of
      # Faraday::Connection (that's what stub_any_instance's define_method
      # trick does), `self` inside it is the actual Connection object being
      # posted through, so `url_prefix` reads that Connection's configured
      # base URL, which is exactly the webhook URL AlertDeliveryService
      # constructed the Connection with. Storing `.to_s` of it into the
      # `posted_to` variable declared outside is how the test captures
      # "which URL did the code actually try to post to."
      posted_to = url_prefix.to_s
      # The lambda's last expression is its return value, returning the
      # fake response object here means the calling code (deliver_discord)
      # receives it exactly as if a real POST had succeeded.
      fake_response
    }) do
      AlertDeliveryService.deliver(rule, alert_message)
    end
    # `end` closes the `stub_any_instance(...) do ... end` block above.

    # `assert_match "rule/specific", posted_to` checks that the captured
    # `posted_to` string CONTAINS "rule/specific", proving the
    # rule-specific webhook URL was used instead of the global default one
    # (which contains "global/default" instead).
    assert_match "rule/specific", posted_to
  end
  # `end` closes the "deliver_discord posts to the rule's webhook URL..."
  # test block above.

  test "deliver_discord handles a non-success response without raising" do
    Setting.set("discord_enabled", "true")
    rule = alert_rules(:price_threshold_rule)
    rule.update!(discord_webhook_url: "https://discord.com/api/webhooks/x/y")

    # This time `success?` is `false` and `status` is `404`, simulating
    # Discord rejecting the webhook (e.g. because the channel/webhook was
    # deleted). The test's job is to confirm AlertDeliveryService's
    # non-success branch handles this gracefully (logs it) rather than
    # raising an unhandled exception.
    fake_response = Struct.new(:success?, :status, :body).new(false, 404, "Unknown Webhook")

    # This fake `.post` implementation ignores its block entirely (`&blk`
    # is captured but never called) and just returns the failure response
    # directly, simpler than the previous test because this one doesn't
    # need to inspect what was posted, only how the response is handled.
    stub_any_instance(Faraday::Connection, :post, ->(&blk) { fake_response }) do
      AlertDeliveryService.deliver(rule, alert_message) # would raise if the non-success branch didn't handle it
    end
    assert true
  end
  # `end` closes the "deliver_discord handles a non-success response..."
  # test block above.

  test "deliver_discord handles a connection failure without raising" do
    Setting.set("discord_enabled", "true")
    rule = alert_rules(:price_threshold_rule)
    rule.update!(discord_webhook_url: "https://discord.com/api/webhooks/x/y")

    # This fake `.post` implementation raises Faraday::ConnectionFailed,
    # the real exception Faraday raises when it can't establish a TCP
    # connection at all (as opposed to getting an HTTP error response back,
    # which is what the previous test simulated). This confirms
    # AlertDeliveryService's `rescue Faraday::ConnectionFailed` branch (see
    # app/services/alerting/alert_delivery_service.rb) catches this and
    # logs it instead of letting it crash the whole alert-checking job.
    stub_any_instance(Faraday::Connection, :post, ->(*) { raise Faraday::ConnectionFailed, "refused" }) do
      AlertDeliveryService.deliver(rule, alert_message)
    end
    assert true
  end
  # `end` closes the "deliver_discord handles a connection failure..." test block above.
end
# `end` closes the `class AlertDeliveryServiceTest < ActiveSupport::TestCase`
# definition that started at the top of this file.
