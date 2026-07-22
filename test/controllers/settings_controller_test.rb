require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "index succeeds" do
    get settings_path
    assert_response :success
  end

  test "update saves a text setting" do
    patch settings_path, params: { settings: { "email_smtp_host" => "smtp.new-host.com" } }
    assert_redirected_to settings_path
    assert_equal "smtp.new-host.com", Setting.get("email_smtp_host")
  end

  test "update ignores unknown setting keys (form tampering protection)" do
    patch settings_path, params: { settings: { "not_a_real_setting" => "value" } }
    assert_redirected_to settings_path
    assert_nil Setting.find_by(key: "not_a_real_setting")
  end

  test "update treats a checked boolean checkbox as true" do
    patch settings_path, params: {
      settings: { "crawl_headless" => "true", "crawl_headless_unchecked" => "false" }
    }
    assert_equal true, Setting.get("crawl_headless")
  end

  test "update treats an unchecked boolean checkbox as false" do
    Setting.set("crawl_headless", "true")

    patch settings_path, params: {
      settings: { "crawl_headless_unchecked" => "false" }
    }
    assert_equal false, Setting.get("crawl_headless")
  end

  test "update skips a blank password field instead of wiping out the stored value" do
    Setting.set("email_smtp_password", "super-secret")

    patch settings_path, params: { settings: { "email_smtp_password" => "" } }

    assert_equal "super-secret", Setting.get("email_smtp_password")
  end

  test "update saves a non-blank password field" do
    patch settings_path, params: { settings: { "email_smtp_password" => "new-secret" } }
    assert_equal "new-secret", Setting.get("email_smtp_password")
  end

  test "test_email fails cleanly when no recipient is configured" do
    Setting.set("email_to_address", "")

    post test_email_settings_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    refute body["success"]
    assert_match(/No recipient/, body["message"])
  end

  test "test_discord fails cleanly when no webhook is configured" do
    Setting.set("discord_webhook_url", "")

    post test_discord_settings_path, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    refute body["success"]
    assert_match(/No Discord webhook/, body["message"])
  end

  test "test_discord reports a connection failure without raising" do
    Setting.set("discord_webhook_url", "https://discord.com/api/webhooks/x/y")

    stub_any_instance(Faraday::Connection, :post, ->(*) { raise Faraday::ConnectionFailed, "connection refused" }) do
      post test_discord_settings_path, as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    refute body["success"]
    assert_match(/Could not connect/, body["message"])
  end
end
