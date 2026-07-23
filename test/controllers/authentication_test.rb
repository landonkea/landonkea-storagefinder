# `require` loads test_helper.rb before anything else in this file runs —
# it wires up the Rails test environment, database, and (importantly for
# this file) the `basic_auth_header` helper method used below.
require "test_helper"

# Exercises the HTTP Basic Auth gate in ApplicationController directly,
# bypassing the global header injection in test_helper.rb so we can prove
# the gate actually rejects unauthenticated/incorrect requests (every other
# controller test relies on that header being required, so it's worth
# confirming it isn't a no-op).
#
# `class AuthenticationTest < ActionDispatch::IntegrationTest` declares this
# class as a Rails integration test. Inheriting from ActionDispatch::
# IntegrationTest gives it request-simulating helpers (`get`, `post`, etc.)
# that send a request through the app's real routing/controller stack
# in-process, without opening an actual network socket or browser.
class AuthenticationTest < ActionDispatch::IntegrationTest
  # `test "..." do ... end` is Minitest/Rails syntax that defines one test
  # case; the string becomes the test's name and the block is its body.
  test "rejects requests with no credentials" do
    # test_helper.rb's process override auto-injects valid credentials into
    # every request in this suite (see basic_auth_header) — explicitly
    # nil-ing the header here is what actually leaves it off the request.
    #
    # `get root_path` simulates a browser GET request to the app's root
    # ("/") URL. `headers:` is a keyword argument letting the test supply
    # raw HTTP headers for the simulated request — here it's a Ruby Hash
    # literal `{ "HTTP_AUTHORIZATION" => nil }` where the key is Rack's
    # internal name for the "Authorization" HTTP header and the value `nil`
    # (Ruby's "nothing"/absence value) overrides test_helper.rb's default
    # auto-injected header, so this specific request goes out with NO
    # Authorization header at all — simulating a visitor who never logged
    # in.
    get root_path, headers: { "HTTP_AUTHORIZATION" => nil }
    # `assert_response :unauthorized` checks the response's HTTP status
    # code was 401 Unauthorized — the standard status for "you didn't
    # provide valid credentials," confirming ApplicationController's Basic
    # Auth gate actually blocks the request instead of letting it through.
    assert_response :unauthorized
  end
  # `end` closes the "rejects requests with no credentials" test block.

  test "rejects requests with incorrect credentials" do
    # Builds an Authorization header with a WRONG username/password pair
    # (both literally "wrong"), to prove the gate checks the actual
    # credential values and not just "some header was present."
    # `ActionController::HttpAuthentication::Basic.encode_credentials` is
    # the same Rails helper real HTTP Basic Auth clients use — it takes a
    # username and password and returns the properly formatted
    # "Basic <base64-encoded-string>" value that belongs in an Authorization
    # header.
    get root_path, headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong")
    }
    # The `}` above closes the `headers: { ... }` hash literal opened two
    # lines up. Still expecting a 401, since the credentials don't match the
    # real ones.
    assert_response :unauthorized
  end
  # `end` closes the "rejects requests with incorrect credentials" test
  # block.

  test "accepts requests with correct credentials" do
    # `basic_auth_header` is the helper method defined in test_helper.rb
    # (see the note in that file) — it builds a correctly-encoded
    # Authorization header from the real app credentials configured for the
    # test environment. Passing it explicitly here (rather than relying on
    # the auto-injection every other test benefits from) makes this test's
    # intent — "correct credentials should be let through" — explicit and
    # self-contained.
    get root_path, headers: basic_auth_header
    # A 2xx ("success") status here proves valid credentials pass the gate,
    # completing the pair of assertions with the two rejection tests above:
    # the gate isn't a no-op, and it isn't overly strict either.
    assert_response :success
  end
  # `end` closes the "accepts requests with correct credentials" test block.
end
# `end` closes the `class AuthenticationTest < ActionDispatch::IntegrationTest`
# definition that started at the top of the file.
