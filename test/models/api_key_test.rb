require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  test "requires a name" do
    api_key = ApiKey.new
    assert_not api_key.valid?
    assert_includes api_key.errors[:name], "A label is required so you can tell keys apart"
  end

  test "auto-generates a unique token on save" do
    api_key = ApiKey.create!(name: "Test integration")
    assert api_key.token.present?
  end

  test "generates different tokens for different keys" do
    first  = ApiKey.create!(name: "First")
    second = ApiKey.create!(name: "Second")
    assert_not_equal first.token, second.token
  end

  test "active scope only returns active keys" do
    active_key   = ApiKey.create!(name: "Active", active: true)
    inactive_key = ApiKey.create!(name: "Inactive", active: false)

    assert_includes ApiKey.active, active_key
    assert_not_includes ApiKey.active, inactive_key
  end

  test "record_usage! bumps request_count and sets last_used_at" do
    api_key = ApiKey.create!(name: "Test integration")
    assert_equal 0, api_key.request_count
    assert_nil api_key.last_used_at

    api_key.record_usage!
    api_key.reload

    assert_equal 1, api_key.request_count
    assert api_key.last_used_at.present?
  end

  test "regenerate_token issues a new token" do
    api_key = ApiKey.create!(name: "Test integration")
    original_token = api_key.token

    api_key.regenerate_token

    assert_not_equal original_token, api_key.token
  end

  test "masked_token hides the middle of the token" do
    api_key = ApiKey.create!(name: "Test integration")
    masked = api_key.masked_token

    assert masked.start_with?(api_key.token[0, 4])
    assert masked.end_with?(api_key.token[-4, 4])
    assert_not_equal api_key.token, masked
  end
end
