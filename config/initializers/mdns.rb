# =============================================================================
# mDNS / ZEROCONF CONFIGURATION
# =============================================================================
# This makes the app discoverable at storagefinder.local on your LAN.
# Any device on the same network can access it without editing hosts files.
#
# mDNS (Multicast DNS) is the technology behind Bonjour (Mac/iOS) and
# Avahi (Linux). It broadcasts the app's hostname and port on the local network.
#
# Requirements:
#   - Linux: install avahi-daemon (usually already installed)
#   - Mac: Bonjour is built-in
#   - Windows: Bonjour for Windows or mDNS-SD
#
# The dnssd gem provides a Ruby interface to the OS-level mDNS daemon.
# =============================================================================

# Only run mDNS announcement if dnssd gem is available and not in test mode
if !Rails.env.test?
  begin
    require "dnssd"

    # The port Rails is listening on
    # Port is set in start.sh — currently 5555
    port = ENV.fetch("PORT", 5555).to_i

    # Announce the app on the local network
    # This runs in a background thread so it doesn't block app startup
    Thread.new do
      begin
        # Register the service as HTTP on port PORT
        # "_http._tcp" is the standard mDNS service type for web apps
        DNSSD.register("StorageFinder", "_http._tcp", nil, port) do |reply|
          Rails.logger.info(
            "[mDNS] Registered as '#{reply.name}' on port #{port} — " \
            "access at http://storagefinder.local:#{port == 80 ? "" : port}"
          )
        end

        # Keep the thread alive — mDNS registration is maintained as long as the thread runs
        sleep

      rescue => e
        Rails.logger.warn(
          "[mDNS] Could not register mDNS service: #{e.class}: #{e.message}. " \
          "The app will still work, but other LAN devices must use the IP address instead of storagefinder.local. " \
          "On Linux, ensure avahi-daemon is installed: sudo apt install avahi-daemon"
        )
      end
    end

    Rails.logger.info("[mDNS] Starting mDNS announcement for storagefinder.local...")

  rescue LoadError
    Rails.logger.warn(
      "[mDNS] dnssd gem not available. " \
      "storagefinder.local hostname will not work on other LAN devices. " \
      "Run: gem install dnssd  or add it to Gemfile and run bundle install."
    )
  rescue => e
    Rails.logger.warn("[mDNS] mDNS initialization error: #{e.class}: #{e.message}")
  end
end
