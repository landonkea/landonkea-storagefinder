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
# (This box comment was already here and explains the overall purpose of the
# file. Background for a novice: like every file in config/initializers/,
# this code runs exactly once, automatically, when the Rails app boots, see
# config/initializers/assets.rb for a full explanation of what an
# "initializer" is. This particular one doesn't configure a setting on
# `config` the way most initializers do, instead it directly runs Ruby code
# that starts a background thread announcing this app's presence on the
# local network, so that typing "storagefinder.local" in a browser on
# another device on the same LAN resolves to this machine, without anyone
# needing to edit that other device's hosts file or know its raw IP address.)

# Blank line, purely visual spacing, has no effect on Ruby.

# A comment explaining the `if` condition below: mDNS announcement is
# something a real, long-running server process should do, it makes no
# sense (and would be actively unwanted noise) while running the automated
# test suite, which boots and tears down the app repeatedly and isn't meant
# to broadcast anything onto a real network.
# Only run mDNS announcement if dnssd gem is available and not in test mode
# `if` starts a conditional, everything until the matching `end` at the
# bottom of this file only runs when the condition here is true.
# `Rails.env` returns the current environment as a special String-like
# object (e.g. "development", "test", "production"); `.test?` is a
# convenience method it provides, true only when the environment is
# exactly "test". The leading `!` is Ruby's "not" operator, flipping true to
# false and vice versa, so this whole condition reads as "if the current
# environment is NOT test."
if !Rails.env.test?
  # `begin ... rescue ... end` is Ruby's exception-handling construct: code
  # inside the `begin` block runs normally; if it raises an error/exception,
  # execution jumps to a matching `rescue` clause below instead of crashing
  # the whole application. This outer `begin` specifically guards against
  # the `require "dnssd"` line right below possibly failing.
  begin
    # `require "dnssd"` loads the "dnssd" Ruby gem, which wraps the
    # operating system's own mDNS daemon (Avahi on Linux, Bonjour on Mac/
    # Windows, as the box comment above explains) so Ruby code can register
    # a network service through it. If this gem isn't installed at all,
    # `require` raises a `LoadError`, handled by the `rescue LoadError`
    # clause much further down this file.
    require "dnssd"

    # Blank line, purely visual spacing, has no effect on Ruby.

    # A comment explaining the line below: it introduces which network port
    # gets announced.
    # The port Rails is listening on
    # Port is set in start.sh, currently 5555
    # `ENV.fetch("PORT", 5555)` reads the PORT environment variable if it's
    # set, falling back to the plain Integer `5555` (the default value,
    # passed as `.fetch`'s second argument) if that environment variable
    # was never set at all. `.to_i` then converts whatever was read into an
    # Integer, necessary because environment variables are always read as
    # Strings (even the fallback default get run through `.to_i` here,
    # which is harmless since converting an Integer via `.to_i` just
    # returns that same Integer unchanged). The result is stored in the
    # local variable `port` for reuse below.
    port = ENV.fetch("PORT", 5555).to_i

    # Blank line, purely visual spacing, has no effect on Ruby.

    # A comment explaining the block below: it introduces what the
    # `Thread.new do ... end` call does, starts running its block
    # concurrently, on a separate thread, rather than blocking (pausing)
    # the rest of this initializer, and by extension the whole app boot
    # process, while mDNS registration and its `sleep` (further below) run.
    # Announce the app on the local network
    # This runs in a background thread so it doesn't block app startup
    # `Thread.new` creates and immediately starts running a new Ruby Thread
    # (a separate, concurrently-executing sequence of code sharing the same
    # process); `do ... end` is the block of code that thread will run.
    Thread.new do
      # A nested `begin ... rescue ... end`, this one specifically guards
      # the mDNS registration/sleep logic running inside this background
      # thread, so that if anything inside goes wrong, it's caught and
      # logged rather than silently killing this background thread (which
      # would happen by default, an unhandled exception in a Ruby Thread
      # doesn't crash the whole process, but does terminate that one thread
      # and, without this rescue, the error would go unnoticed).
      begin
        # A comment explaining the two lines below together: registering
        # this specific process as a discoverable HTTP service via mDNS.
        # Register the service as HTTP on port PORT
        # "_http._tcp" is the standard mDNS service type for web apps
        # `DNSSD.register(...)` is the dnssd gem's method for announcing a
        # network service. Its arguments, in order: `"StorageFinder"` (the
        # human-readable name this service advertises itself as);
        # `"_http._tcp"` (a String naming the standard mDNS service-type
        # code for "a web server reachable over TCP", other services, like
        # printers, use different codes); `nil` (the domain to register in
        # , `nil` means "use the default," normally "local"); and `port`
        # (the local variable holding the port number computed above).
        # `do |reply| ... end` is a block that DNSSD will call once
        # registration succeeds, receiving a `reply` object describing the
        # actual registered service.
        DNSSD.register("StorageFinder", "_http._tcp", nil, port) do |reply|
          # `Rails.logger` is the app's shared logging object. `.info`
          # writes a message at the "info" severity level. The String
          # argument is built across two lines joined by a trailing `\`
          # (backslash) at the end of the first line, Ruby's line-
          # continuation syntax, letting one logical String literal span
          # multiple source lines for readability. It uses STRING
          # INTERPOLATION (`#{...}`) twice: `#{reply.name}` inserts the
          # actual registered service name reported back by mDNS, and
          # `#{port == 80 ? "" : port}` is a one-line CONDITIONAL
          # (TERNARY) expression, `condition ? value_if_true :
          # value_if_false`, that omits the port number from the printed
          # URL when it's the default HTTP port 80 (since a browser assumes
          # port 80 automatically), printing it explicitly otherwise.
          Rails.logger.info(
            "[mDNS] Registered as '#{reply.name}' on port #{port}, " \
            "access at http://storagefinder.local:#{port == 80 ? "" : port}"
          )
        end
        # `end` closes the `do |reply| ... end` block passed to
        # `DNSSD.register` above, this block only runs once registration
        # actually succeeds/reports back.

        # Blank line, purely visual spacing, has no effect on Ruby.

        # A comment explaining the line below: without something to keep
        # this background thread alive, it would simply finish executing
        # (falling off the end of its `do ... end` block) and exit right
        # after registering, which would likely tear down the mDNS
        # registration along with it.
        # Keep the thread alive, mDNS registration is maintained as long as the thread runs
        # `sleep` with no argument pauses this thread indefinitely (forever,
        # or until the whole process exits), its sole purpose here is to
        # keep this background thread alive so the mDNS registration set up
        # above remains active for as long as the app keeps running.
        sleep

      # Blank line, purely visual spacing, has no effect on Ruby.

      # `rescue => e` catches ANY StandardError-descendant exception raised
      # anywhere in the `begin` block above (registration failing, the
      # `sleep` being interrupted unexpectedly, etc.) and stores the caught
      # exception object in the local variable `e` for use in the log
      # message below, instead of letting this background thread die
      # silently.
      rescue => e
        # Logs a WARNING (less severe than an error, the app keeps
        # running fine without mDNS) explaining what happened and how to
        # fix it. `#{e.class}` interpolates the specific exception class
        # that was raised (e.g. `RuntimeError`); `#{e.message}` interpolates
        # that exception's own descriptive message. The String again uses
        # backslash line-continuation to span multiple source lines as one
        # logical message.
        Rails.logger.warn(
          "[mDNS] Could not register mDNS service: #{e.class}: #{e.message}. " \
          "The app will still work, but other LAN devices must use the IP address instead of storagefinder.local. " \
          "On Linux, ensure avahi-daemon is installed: sudo apt install avahi-daemon"
        )
      end
      # `end` closes the inner `begin ... rescue => e ... end` block that
      # wraps the registration/sleep logic running inside this thread.
    end
    # `end` closes the `Thread.new do ... end` block, everything above,
    # inside it, actually runs concurrently on the new background thread,
    # not immediately/synchronously as this initializer file is read.

    # Blank line, purely visual spacing, has no effect on Ruby.

    # Logs an info-level message on the MAIN thread (not inside the
    # background thread above) confirming that starting the announcement
    # process has been kicked off, this line runs right after `Thread.new`
    # returns, which happens almost immediately, well before the new
    # thread's own registration/logging necessarily completes.
    Rails.logger.info("[mDNS] Starting mDNS announcement for storagefinder.local...")

  # Blank line, purely visual spacing, has no effect on Ruby.

  # `rescue LoadError` catches specifically the error type raised earlier if
  # `require "dnssd"` failed because the gem isn't installed at all, as
  # opposed to the generic `rescue => e` below, which catches any OTHER kind
  # of error.
  rescue LoadError
    # Logs a warning explaining that the whole mDNS feature is unavailable
    # because the required gem is missing, along with instructions for
    # installing it, using the same backslash line-continuation string
    # syntax explained above.
    Rails.logger.warn(
      "[mDNS] dnssd gem not available. " \
      "storagefinder.local hostname will not work on other LAN devices. " \
      "Run: gem install dnssd  or add it to Gemfile and run bundle install."
    )
  # `rescue => e` here catches any OTHER kind of exception (not a
  # `LoadError`) that might occur anywhere in the OUTER `begin` block,
  # e.g. if `DNSSD.register` itself raised something synchronously before
  # even reaching `Thread.new`, or some unexpected setup failure.
  rescue => e
    # Logs a shorter warning for this catch-all case, again interpolating
    # the exception's class and message.
    Rails.logger.warn("[mDNS] mDNS initialization error: #{e.class}: #{e.message}")
  end
  # `end` closes the OUTER `begin ... rescue LoadError ... rescue => e ...
  # end` block that wraps this entire mDNS setup attempt.
end
# `end` closes the `if !Rails.env.test?` conditional opened at the top of
# this file, none of the code above runs at all while running the
# automated test suite.
