# `module` groups related classes under one namespace (a named container),
# so `ApplicationCable::Channel` and `ApplicationCable::Connection` are kept
# separate from any unrelated `Channel` or `Connection` class elsewhere in
# the app. Rails' ActionCable generator creates this file automatically.
module ApplicationCable
  # ActionCable is Rails' framework for WebSockets — a persistent, two-way
  # connection between the browser and the server that lets the server push
  # data to the browser instantly (e.g. live crawl progress), instead of the
  # browser having to repeatedly ask "anything new?" (polling).
  #
  # A "channel" is one topic/feature that streams data over that connection
  # (this app has one: CrawlProgressChannel, in
  # app/channels/crawl_progress_channel.rb). Every channel class must inherit
  # from (be built on top of) `ActionCable::Channel::Base`, Rails' built-in
  # base channel class that provides the subscribe/unsubscribe/stream_from
  # machinery. `class Channel < ActionCable::Channel::Base` declares this
  # class as that shared base for every channel in the app.
  class Channel < ActionCable::Channel::Base
  end
  # `end` closes the `class Channel` definition opened above. The class body
  # is empty — this file exists only to provide a shared parent class that
  # other channels (like CrawlProgressChannel) inherit from; any behavior
  # common to ALL channels would be added here, but this app doesn't need any.
end
# `end` closes the `module ApplicationCable` block opened at the top of the file.
