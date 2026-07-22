module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # No authentication needed — this is a local LAN app
  end
end
