require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "get returns the cast value for an existing key" do
    assert_equal 100, Setting.get("crawl_default_radius_miles")
    assert_equal true, Setting.get("crawl_headless")
    assert_equal "smtp.gmail.com", Setting.get("email_smtp_host")
  end

  test "get returns the default when the key doesn't exist" do
    assert_nil Setting.get("nonexistent_key")
    assert_equal "fallback", Setting.get("nonexistent_key", default: "fallback")
  end

  test "set updates an existing setting's value" do
    Setting.set("crawl_default_radius_miles", "250")
    assert_equal 250, Setting.get("crawl_default_radius_miles")
  end

  test "set creates a new setting when the key doesn't already exist" do
    assert_nil Setting.find_by(key: "brand_new_key")
    Setting.set("brand_new_key", "hello")
    assert_equal "hello", Setting.find_by(key: "brand_new_key").value
  end

  test "enabled? returns true only for boolean settings set to true" do
    assert Setting.enabled?("crawl_headless")
    refute Setting.enabled?("email_enabled")
  end

  test "get_all scopes to a category" do
    email_settings = Setting.get_all("email")
    assert email_settings.key?("email_smtp_host")
    refute email_settings.key?("crawl_headless")
  end

  test "value is stored encrypted in the database" do
    setting = settings(:email_smtp_host)

    raw_value = ActiveRecord::Base.connection.select_value(
      "SELECT value FROM settings WHERE id = #{setting.id}"
    )

    refute_equal "smtp.gmail.com", raw_value, "raw DB column should not contain the plaintext value"
    assert_equal "smtp.gmail.com", setting.reload.value, "AR-level access should transparently decrypt"
  end

  test "key must be unique" do
    duplicate = Setting.new(key: settings(:email_enabled).key, value: "x", input_type: "text")
    refute duplicate.valid?
    assert_includes duplicate.errors[:key], "A setting with this key already exists"
  end
end
