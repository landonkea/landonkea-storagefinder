require "test_helper"

# Exercises the HTTP Basic Auth gate in ApplicationController directly,
# bypassing the global header injection in test_helper.rb so we can prove
# the gate actually rejects unauthenticated/incorrect requests (every other
# controller test relies on that header being required, so it's worth
# confirming it isn't a no-op).
class AuthenticationTest < ActionDispatch::IntegrationTest
  test "rejects requests with no credentials" do
    # test_helper.rb's process override auto-injects valid credentials into
    # every request in this suite (see basic_auth_header) — explicitly
    # nil-ing the header here is what actually leaves it off the request.
    get root_path, headers: { "HTTP_AUTHORIZATION" => nil }
    assert_response :unauthorized
  end

  test "rejects requests with incorrect credentials" do
    get root_path, headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong")
    }
    assert_response :unauthorized
  end

  test "accepts requests with correct credentials" do
    get root_path, headers: basic_auth_header
    assert_response :success
  end
end
