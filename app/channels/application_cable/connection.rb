# `module` groups related classes under one namespace (a named container),
# see app/channels/application_cable/channel.rb for the same pattern.
module ApplicationCable
  # A "Connection" represents one browser's WebSocket connection to this
  # server, the underlying pipe that one or more "channels" (see
  # app/channels/crawl_progress_channel.rb) send messages over. Every
  # ActionCable app needs exactly one Connection class, inheriting from (built
  # on top of) Rails' `ActionCable::Connection::Base`, which handles the raw
  # WebSocket handshake and message routing. This is where authentication for
  # WebSocket connections belongs, contrast with ApplicationController, which
  # gates ordinary HTTP requests behind a username/password
  # (http_basic_authenticate_with): that protection does NOT automatically
  # extend to WebSocket connections, since they connect directly to this
  # class instead of going through a controller. README.md used to flag this
  # as a known gap (`/cable` bypassing Basic Auth entirely), the `connect`
  # method below closes it.
  class Connection < ActionCable::Connection::Base
    # `identified_by` declares which attribute(s) this connection is
    # "identified by" once authenticated, ActionCable requires at least one
    # (it uses it to let a later part of the app find/disconnect a specific
    # connection by identity, though this single-user app never actually
    # does that lookup). There's no per-user account system here (see
    # ApplicationController's own note on this), so there's no real user
    # identity to store, `:authenticated_client` just records that SOME
    # connection successfully passed the Basic Auth check below, as a plain
    # boolean-ish marker rather than a real user record.
    identified_by :authenticated_client

    # `connect` is an ActionCable lifecycle method: it runs once, right when
    # a browser's WebSocket handshake request first arrives, BEFORE any
    # channel subscription is allowed. Rejecting the connection here (via
    # `reject_unauthorized_connection` below) stops the WebSocket from ever
    # being established at all.
    def connect
      self.authenticated_client = authenticate_with_basic_auth!
    end

    private

    # Re-checks the same username/password ApplicationController's
    # `http_basic_authenticate_with` validates for ordinary HTTP requests,
    # see that class for where the expected credentials come from
    # (`Rails.application.credentials.dig(:auth, ...)`). Browsers that have
    # already authenticated against this app's HTTP Basic Auth prompt
    # automatically re-send the same `Authorization` header on same-origin
    # requests, including the WebSocket upgrade request that opens this
    # connection, so a browser tab that's already logged in doesn't need to
    # log in again just for `/cable`; one that never authenticated (e.g. a
    # bare `wscat`/curl connection from off this app's own pages) does not
    # have that header and gets rejected below.
    def authenticate_with_basic_auth!
      # `ActionController::HttpAuthentication::Basic.user_name_and_password`
      # parses the raw `Authorization: Basic ...` header off the WebSocket
      # handshake request (`request` here is the same kind of request object
      # a controller sees, made available to every ActionCable::Connection),
      # returning a two-element Array `[username, password]`, both `nil` if
      # the header is missing entirely.
      username, password = ActionController::HttpAuthentication::Basic.user_name_and_password(request)

      expected_username = Rails.application.credentials.dig(:auth, :username).to_s
      expected_password = Rails.application.credentials.dig(:auth, :password).to_s

      # `ActiveSupport::SecurityUtils.secure_compare` compares two strings in
      # CONSTANT time (the comparison always takes the same amount of time
      # regardless of how many leading characters match), an ordinary `==`
      # comparison can leak, via how long it takes to respond, how many
      # characters of a guessed password were correct, letting an attacker
      # slowly narrow down the real password one character at a time. `.to_s`
      # above guards against `nil` (e.g. credentials never configured, or no
      # Authorization header at all giving `username`/`password` as `nil`)
      # , `secure_compare` requires real strings, and comparing two empty
      # strings is safely just "not a match" rather than raising an error.
      return true if username.present? &&
        ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_username) &&
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)

      # `reject_unauthorized_connection` is an ActionCable::Connection::Base
      # method: it immediately halts the WebSocket handshake and closes the
      # connection, the WebSocket equivalent of an HTTP 401 Unauthorized
      # response, the browser's `/cable` subscription attempt simply fails
      # to connect at all.
      reject_unauthorized_connection
    end
  end
  # `end` closes the `class Connection` definition opened above.
end
# `end` closes the `module ApplicationCable` block opened at the top of the file.
