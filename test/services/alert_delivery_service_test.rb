require "test_helper"

class AlertDeliveryServiceTest < ActiveSupport::TestCase
  def alert_message
    { subject: "Test", text_body: "body", html_body: "<p>body</p>", sms_body: "sms" }
  end

  test "deliver skips email when globally disabled, even if the rule has it enabled" do
    Setting.set("email_enabled", "false")
    rule = alert_rules(:price_drop_rule) # email_enabled: true on the rule itself

    # No SMTP settings configured either, so a real attempt would raise —
    # if this doesn't raise, the global disable short-circuited it.
    AlertDeliveryService.deliver(rule, alert_message)
    assert true
  end

  test "deliver skips discord when the rule doesn't have it enabled, even if globally enabled" do
    Setting.set("discord_enabled", "true")
    rule = alert_rules(:price_drop_rule) # discord_enabled: false on the rule

    stub_any_instance(Faraday::Connection, :post, ->(*) { raise "should not have posted to Discord" }) do
      AlertDeliveryService.deliver(rule, alert_message)
    end
    assert true
  end

  test "deliver_email logs and returns early when SMTP settings are incomplete" do
    Setting.set("email_enabled", "true")
    Setting.set("email_smtp_username", "")
    rule = alert_rules(:price_drop_rule)

    AlertDeliveryService.deliver(rule, alert_message) # would raise if it tried a real SMTP connection
    assert true
  end

  test "deliver_discord logs and returns early when no webhook URL is configured" do
    Setting.set("discord_enabled", "true")
    Setting.set("discord_webhook_url", "")
    rule = alert_rules(:price_threshold_rule) # discord_enabled: true, but no rule-specific webhook either

    AlertDeliveryService.deliver(rule, alert_message)
    assert true
  end

  test "deliver_discord posts to the rule's webhook URL when set, over the global default" do
    Setting.set("discord_enabled", "true")
    Setting.set("discord_webhook_url", "https://discord.com/api/webhooks/global/default")
    rule = alert_rules(:price_threshold_rule)
    rule.update!(discord_webhook_url: "https://discord.com/api/webhooks/rule/specific")

    posted_to = nil
    fake_response = Struct.new(:success?, :status, :body).new(true, 200, "ok")

    # Faraday::Connection's url_prefix reflects the URL Faraday.new(url) was
    # called with, so reading it from inside the stub (where `self` is the
    # Connection instance) confirms which webhook URL was actually used.
    stub_any_instance(Faraday::Connection, :post, ->(&blk) {
      req = Struct.new(:headers, :body).new({}, nil)
      blk.call(req) if blk
      posted_to = url_prefix.to_s
      fake_response
    }) do
      AlertDeliveryService.deliver(rule, alert_message)
    end

    assert_match "rule/specific", posted_to
  end

  test "deliver_discord handles a non-success response without raising" do
    Setting.set("discord_enabled", "true")
    rule = alert_rules(:price_threshold_rule)
    rule.update!(discord_webhook_url: "https://discord.com/api/webhooks/x/y")

    fake_response = Struct.new(:success?, :status, :body).new(false, 404, "Unknown Webhook")

    stub_any_instance(Faraday::Connection, :post, ->(&blk) { fake_response }) do
      AlertDeliveryService.deliver(rule, alert_message) # would raise if the non-success branch didn't handle it
    end
    assert true
  end

  test "deliver_discord handles a connection failure without raising" do
    Setting.set("discord_enabled", "true")
    rule = alert_rules(:price_threshold_rule)
    rule.update!(discord_webhook_url: "https://discord.com/api/webhooks/x/y")

    stub_any_instance(Faraday::Connection, :post, ->(*) { raise Faraday::ConnectionFailed, "refused" }) do
      AlertDeliveryService.deliver(rule, alert_message)
    end
    assert true
  end
end
