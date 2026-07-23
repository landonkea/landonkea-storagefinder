# `module` groups related classes under one namespace (a named container) —
# see app/channels/application_cable/channel.rb for the same pattern.
module ApplicationCable
  # A "Connection" represents one browser's WebSocket connection to this
  # server — the underlying pipe that one or more "channels" (see
  # app/channels/crawl_progress_channel.rb) send messages over. Every
  # ActionCable app needs exactly one Connection class, inheriting from (built
  # on top of) Rails' `ActionCable::Connection::Base`, which handles the raw
  # WebSocket handshake and message routing. This is where you'd normally put
  # authentication — e.g. checking a login cookie — before letting a browser
  # open a WebSocket connection at all.
  class Connection < ActionCable::Connection::Base
    # This app is a single-user tool meant to run on your own LAN (local
    # network), not the public internet — there's no login system, so there's
    # nothing to check here before accepting a connection. Contrast this with
    # ApplicationController, which DOES gate HTTP requests behind a
    # username/password (http_basic_authenticate_with) — that protection
    # does NOT extend to WebSocket connections, since they connect directly
    # to this class instead of going through a controller. This is a plain
    # Ruby comment (not executable code) left as a note explaining the
    # absence of authentication logic below.
    # No authentication needed — this is a local LAN app
  end
  # `end` closes the `class Connection` definition opened above.
end
# `end` closes the `module ApplicationCable` block opened at the top of the file.
