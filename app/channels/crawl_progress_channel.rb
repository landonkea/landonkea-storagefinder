# =============================================================================
# CRAWL PROGRESS CHANNEL
# =============================================================================
# This ActionCable channel pushes live progress messages to the dashboard
# during a crawl. The dashboard subscribes to this channel and displays
# log lines and status updates in real time without page refreshes.
#
# The CrawlJob broadcasts to this channel using:
#   ActionCable.server.broadcast("crawl_progress_#{crawl_run.id}", data)
# =============================================================================

# `class CrawlProgressChannel < ApplicationCable::Channel` defines this
# channel as a subclass of (built on top of) ApplicationCable::Channel (see
# app/channels/application_cable/channel.rb), which itself is Rails'
# ActionCable base. A browser "subscribes" to this channel by name (via
# JavaScript, using ActionCable's client library) to start receiving
# messages the server pushes to it — this is the server-side half of that
# subscription.
class CrawlProgressChannel < ApplicationCable::Channel
  # `subscribed` is a special method name ActionCable automatically calls
  # the moment a browser successfully subscribes to this channel. There's no
  # explicit call to it anywhere in this codebase — the ActionCable
  # framework itself invokes it as part of its subscription lifecycle,
  # similar to how Rails calls a controller action when a matching URL is
  # requested.
  def subscribed
    # `params` here holds whatever data the browser's JavaScript sent when
    # it opened the subscription (e.g. { crawl_run_id: 5 }) — conceptually
    # like controller `params`, but coming from the WebSocket subscription
    # request instead of an HTTP request. `.to_i` converts the value to an
    # integer; if it's missing, nil, or not numeric, `.to_i` safely returns
    # 0 rather than raising an error.
    crawl_run_id = params[:crawl_run_id].to_i

    # `.zero?` is true only when crawl_run_id is exactly 0 — i.e. no valid
    # numeric ID was supplied at all (covers both "missing" and "garbage").
    if crawl_run_id.zero?
      # `reject` is an ActionCable method that refuses the subscription —
      # the browser's JavaScript will receive a "rejected" callback instead
      # of successfully connecting to this channel.
      reject   # Refuse the subscription — no (valid) crawl ID provided
      # `return` exits the `subscribed` method immediately, so the code
      # below (which assumes a valid ID) never runs for this case.
      return
    end
    # `end` closes the `if crawl_run_id.zero?` block opened above.

    # Check that this crawl run exists
    # `CrawlRun.exists?(crawl_run_id)` asks the database "is there a row in
    # the crawl_runs table with this ID?" and returns true/false without
    # loading the full record — cheaper than `CrawlRun.find`, which would
    # raise an error if not found. `unless` runs its block only when the
    # condition is FALSE — i.e. only when the crawl run does NOT exist.
    unless CrawlRun.exists?(crawl_run_id)
      # Same rejection mechanism as above, but for a numerically valid ID
      # that doesn't correspond to any real crawl run (e.g. it was deleted,
      # or the browser has a stale/bookmarked ID).
      reject   # Refuse — crawl run doesn't exist
      # Exit early — nothing further should run for a rejected subscription.
      return
    end
    # `end` closes the `unless CrawlRun.exists?(crawl_run_id)` block above.

    # Subscribe this connection to the stream for this specific crawl
    # Broadcasts to "crawl_progress_123" will be sent to this connection
    # `stream_from` is ActionCable's method for attaching this specific
    # browser connection to a named "stream" (a pub/sub channel by string
    # name). String interpolation (`"#{crawl_run_id}"`) builds a name like
    # "crawl_progress_5" so that only clients watching crawl #5 receive
    # messages broadcast for crawl #5 — other crawls' messages go to their
    # own differently-named streams and are never seen by this connection.
    stream_from "crawl_progress_#{crawl_run_id}"

    # Writes an informational line to the Rails server log, useful for
    # debugging which crawl a given browser tab is watching. `Rails.logger`
    # is Rails' built-in logging object; `.info` marks this as an
    # informational-level message (as opposed to `.warn`, `.error`, `.debug`,
    # etc.). String interpolation again builds the exact stream name into
    # the log message.
    Rails.logger.info("[CrawlProgressChannel] Client subscribed to crawl_progress_#{crawl_run_id}")
  end
  # `end` closes the `def subscribed` method definition opened above.

  # Called when the browser disconnects (page close, refresh, etc.)
  # `unsubscribed` is another special lifecycle method name — like
  # `subscribed`, ActionCable calls this automatically, this time when the
  # connection to this channel ends (tab closed, page navigated away,
  # network drop, etc.). Nothing in this codebase calls it directly.
  def unsubscribed
    # Logs at "debug" level (lower priority than "info" — typically hidden
    # in production logs unless debug logging is explicitly enabled) that a
    # client disconnected. No crawl ID is included here since, unlike
    # `subscribed`, there's no guarantee `params` still reflects a valid
    # subscription at disconnect time.
    Rails.logger.debug("[CrawlProgressChannel] Client unsubscribed")
    # `stop_all_streams` is an ActionCable method that detaches this
    # connection from every stream it was attached to via `stream_from`
    # (there's normally just the one set up in `subscribed` above) — this
    # cleans up server-side resources so the server stops trying to push
    # messages to a browser that's no longer listening.
    stop_all_streams
  end
  # `end` closes the `def unsubscribed` method definition opened above.
end
# `end` closes the `class CrawlProgressChannel` definition opened at the top
# of the file.
