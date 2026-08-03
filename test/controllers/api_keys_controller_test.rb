require "test_helper"

class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  test "index requires basic auth like the rest of the dashboard" do
    get api_keys_path, headers: { "HTTP_AUTHORIZATION" => nil }
    assert_response :unauthorized
  end

  test "index lists existing keys" do
    api_key = ApiKey.create!(name: "Existing key")
    get api_keys_path
    assert_response :success
    assert_match api_key.name, response.body
  end

  test "create issues a new key and shows the raw token once" do
    assert_difference "ApiKey.count", 1 do
      post api_keys_path, params: { api_key: { name: "New integration" } }
    end

    assert_redirected_to api_keys_path
    get api_keys_path
    assert_match ApiKey.last.token, response.body
  end

  test "create with a blank name re-renders the form with an error" do
    assert_no_difference "ApiKey.count" do
      post api_keys_path, params: { api_key: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "destroy revokes and deletes the key" do
    api_key = ApiKey.create!(name: "Doomed key")

    assert_difference "ApiKey.count", -1 do
      delete api_key_path(api_key)
    end

    assert_redirected_to api_keys_path
  end

  test "regenerate rotates the token" do
    api_key = ApiKey.create!(name: "Rotate me")
    original_token = api_key.token

    post regenerate_api_key_path(api_key)

    assert_redirected_to api_keys_path
    assert_not_equal original_token, api_key.reload.token
  end
end
