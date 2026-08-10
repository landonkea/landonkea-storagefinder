# `require "test_helper"` loads the Rails test environment, see the fuller
# explanation of this line in test/controllers/authentication_test.rb.
require "test_helper"

# `ActionCable::Connection::TestCase` (a Rails testing class, distinct from
# `ActionDispatch::IntegrationTest` used elsewhere in this app's test suite)
# is built specifically for unit-testing an ActionCable::Connection class in
# isolation, simulating a WebSocket handshake's `connect` step without
# actually opening a socket. This exercises
# app/channels/application_cable/connection.rb's Basic Auth check directly,
# the same way test/controllers/authentication_test.rb exercises
# ApplicationController's, proving `/cable` is no longer the unauthenticated
# gap README.md used to flag it as.
module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    test "rejects a connection attempt with no Authorization header" do
      # `assert_reject_connection` (provided by ActionCable::Connection::
      # TestCase) asserts that the block raises the specific exception
      # `reject_unauthorized_connection` raises internally, the WebSocket
      # equivalent of asserting a 401 response.
      assert_reject_connection { connect }
    end

    test "rejects a connection attempt with incorrect credentials" do
      assert_reject_connection do
        connect headers: {
          "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong")
        }
      end
    end

    test "accepts a connection attempt with correct credentials" do
      connect headers: basic_auth_header

      # `connection` (provided by ActionCable::Connection::TestCase) is the
      # actual Connection instance `connect` just built, asserting on its
      # `authenticated_client` identifier confirms `connect` set it to `true`
      # via the `identified_by` declaration in connection.rb, rather than
      # merely confirming the connection wasn't rejected.
      assert_equal true, connection.authenticated_client
    end

    private

    # Mirrors test/test_helper.rb's `basic_auth_header` (written for
    # ActionDispatch::IntegrationTest requests), that exact helper isn't
    # available on ActionCable::Connection::TestCase, so it's rebuilt here
    # rather than adding cross-cutting coupling between the two test base
    # classes for one shared line.
    def basic_auth_header
      {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
          Rails.application.credentials.dig(:auth, :username),
          Rails.application.credentials.dig(:auth, :password)
        )
      }
    end
  end
end
