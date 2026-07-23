# =============================================================================
# ALERT DELIVERY SERVICE
# =============================================================================
# Sends alert notifications via Email and/or Discord.
# SMS is wired up structurally but disabled — it requires a paid Twilio account.
# =============================================================================

# Another plain-Ruby "service object" (see app/services/company_registry.rb
# for a full explanation of what that term means) — this one is responsible
# for actually SENDING an already-built alert message out over one or more
# channels (email, Discord, SMS), as opposed to AlertMessageBuilder, which
# only builds the message text/content and doesn't send anything itself.
class AlertDeliveryService
  # Deliver an alert via all channels configured on the rule
  #
  # A convenience class method, same pattern as AlertMessageBuilder.build:
  # build a real instance with `.new`, then immediately call the instance
  # method `.deliver` on it, so callers can just write
  # `AlertDeliveryService.deliver(rule, message)` in one line.
  def self.deliver(rule, message)
    new(rule, message).deliver
  end
  # `end` closes the `def self.deliver` class method definition above.

  # The constructor — automatically runs when `.new(rule, message)` is
  # called, storing both arguments as instance variables (the `@` prefix)
  # so every other method below can read them without needing them passed
  # in again as arguments.
  def initialize(rule, message)
    @rule    = rule
    @message = message
  end
  # `end` closes the `def initialize` method definition above.

  # The main instance method: checks which delivery channels are enabled
  # and, for each one that is, calls the matching private method below.
  def deliver
    # Each line only calls its "deliver_*" method if BOTH conditions after
    # `if` are true: (1) this specific alert RULE has that channel turned
    # on (`@rule.email_enabled?` etc. — presumably a boolean column/method
    # on the AlertRule model), AND (2) the channel is enabled GLOBALLY for
    # the whole app (`Setting.enabled?("email_enabled")` — reading an
    # app-wide setting, likely configurable from a Settings page). Both
    # gates have to be open for that channel to actually fire.
    deliver_email   if @rule.email_enabled?   && Setting.enabled?("email_enabled")
    deliver_discord if @rule.discord_enabled? && Setting.enabled?("discord_enabled")
    deliver_sms     if @rule.sms_enabled?     && Setting.enabled?("sms_enabled")
  end
  # `end` closes the `def deliver` method definition above.

  # `private` marks everything below as internal-only implementation
  # detail — not meant to be called directly from outside this class.
  private

  # ---------------------------------------------------------------------------
  # EMAIL DELIVERY
  # ---------------------------------------------------------------------------
  def deliver_email
    # `Setting.get(...)` reads a configuration value (presumably stored in
    # the database via a Settings admin page) by its name/key. These lines
    # gather every piece of SMTP (the email-sending protocol) configuration
    # needed to send mail.
    smtp_host     = Setting.get("email_smtp_host")
    # `default: 587` supplies a fallback if the setting was never
    # explicitly configured — 587 is the standard SMTP submission port.
    # `.to_i` converts whatever comes back (which could be a String from
    # the database, or the default Integer) into an actual Integer, since
    # a port number needs to be numeric.
    smtp_port     = Setting.get("email_smtp_port", default: 587).to_i
    smtp_username = Setting.get("email_smtp_username")
    smtp_password = Setting.get("email_smtp_password")
    # `||` is Ruby's "or" operator, but here used for a fallback: if
    # email_from_address isn't set (nil), fall back to using the SMTP
    # username as the "from" address instead.
    from_address  = Setting.get("email_from_address") || smtp_username
    # `.presence` is a Rails helper: it returns the value itself if it's
    # "present" (not nil, not blank), or `nil` if it's blank — letting the
    # `||` fallback trigger even if @rule.email_address is an empty string
    # rather than a true `nil`. So: use the rule's own email address if it
    # has one, otherwise fall back to the app-wide default recipient.
    to_address    = @rule.email_address.presence || Setting.get("email_to_address")

    # Validate we have what we need before trying
    #
    # `.blank?` is a Rails helper meaning "nil, empty string, or
    # whitespace-only" — the opposite of `.present?`. This checks that the
    # essential SMTP credentials are all actually configured before
    # attempting to connect.
    if smtp_host.blank? || smtp_username.blank? || smtp_password.blank?
      Rails.logger.error(
        "[AlertDeliveryService] Cannot send email alert — SMTP settings are incomplete. " \
        "Please configure email settings in the Settings page."
      )
      # Bail out early — there's nothing useful we can do without SMTP
      # credentials, so don't attempt to send.
      return
    end
    # `end` closes the SMTP-credentials `if` check above.

    if to_address.blank?
      Rails.logger.error(
        "[AlertDeliveryService] Cannot send email alert — no recipient address configured. " \
        "Set 'Send alerts to' in Settings or specify an email on the alert rule."
      )
      return
    end
    # `end` closes the `if to_address.blank?` check above.

    # `begin ... rescue ... end` wraps the actual email-sending attempt so
    # that any of the various things that can go wrong while talking to an
    # SMTP server (bad credentials, server down, network issue) get caught
    # and logged clearly instead of crashing the whole alert-checking job.
    begin
      # `Mail.new do ... end` uses the `mail` gem's DSL (domain-specific
      # language — a mini vocabulary of methods designed to read almost
      # like plain English for a specific task) to build an email message
      # object. Inside the block, method calls like `from`, `to`, and
      # `subject` are actually setting properties on the message being
      # built, not calling some unrelated global method.
      mail = Mail.new do
        from    from_address
        to      to_address
        subject "StorageFinder Alert: #{@message[:subject]}"

        # `text_part do ... end` defines the plain-text version of the
        # email body (for email clients/situations that can't render
        # HTML). `body @message[:text_body]` sets its content to the
        # pre-built text_body string from AlertMessageBuilder's output.
        text_part do
          body @message[:text_body]
        end
        # `end` closes the `text_part do` block above.

        # `html_part do ... end` defines the rich HTML version of the
        # same email — most modern email clients prefer/render this one
        # when both a text and HTML part are present.
        html_part do
          content_type "text/html; charset=UTF-8"
          body @message[:html_body]
        end
        # `end` closes the `html_part do` block above.
      end
      # `end` closes the `Mail.new do` block above — `mail` now holds a
      # fully-assembled (but not yet sent) email message object.

      # `mail.delivery_method :smtp, { ... }` configures HOW this
      # particular message should be sent — via SMTP, using the settings
      # hash that follows — overriding the app's default mail delivery
      # configuration just for this one message.
      mail.delivery_method :smtp, {
        address:              smtp_host,
        port:                 smtp_port,
        user_name:            smtp_username,
        password:             smtp_password,
        authentication:       :plain,
        enable_starttls_auto: true,  # TLS for Gmail and most providers
        open_timeout:         5,     # Seconds to wait for the TCP connection
        read_timeout:         10     # Seconds to wait for each SMTP response
      }

      # `mail.deliver!` actually connects to the SMTP server and sends the
      # message right now (synchronously — this line blocks until it
      # either succeeds or raises an error). The `!` again signals a
      # meaningful side effect (an email actually goes out).
      mail.deliver!
      Rails.logger.info("[AlertDeliveryService] Email alert sent to #{to_address}")

    # Each `rescue SomeErrorClass => e` below catches a SPECIFIC kind of
    # error and logs a message tailored to that failure mode, so whoever
    # reads the logs gets an actionable hint instead of a generic failure.
    rescue Net::SMTPAuthenticationError => e
      Rails.logger.error(
        "[AlertDeliveryService] SMTP authentication failed. " \
        "Check your username and password (or app password for Gmail). " \
        "Error: #{e.message}"
      )
    rescue Net::SMTPServerBusy, Net::SMTPFatalError => e
      # A single `rescue` clause can list multiple error classes
      # separated by commas — this one catches either kind and handles
      # them the same way.
      Rails.logger.error(
        "[AlertDeliveryService] SMTP server error sending email: #{e.message}"
      )
    rescue => e
      # A catch-all for any other unexpected StandardError not covered by
      # the more specific rescue clauses above.
      Rails.logger.error(
        "[AlertDeliveryService] Unexpected error sending email: #{e.class}: #{e.message}"
      )
    end
    # `end` closes the `begin` block that started the email-sending attempt.
  end
  # `end` closes the `def deliver_email` method definition above.

  # ---------------------------------------------------------------------------
  # DISCORD DELIVERY
  # ---------------------------------------------------------------------------
  def deliver_discord
    # Use the rule's specific webhook URL if set, otherwise fall back to the global one
    #
    # A "webhook" is a URL that, when you POST data to it, triggers an
    # action on the receiving service — here, Discord turns a POST to this
    # URL into a message posted in a specific channel.
    webhook_url = @rule.discord_webhook_url.presence || Setting.get("discord_webhook_url")

    if webhook_url.blank?
      Rails.logger.error(
        "[AlertDeliveryService] Cannot send Discord alert — no webhook URL configured. " \
        "Set a Discord webhook URL in Settings or on the alert rule."
      )
      return
    end
    # `end` closes the `if webhook_url.blank?` check above.

    # Discord webhook payload format
    # The "embeds" array creates a rich formatted card in Discord
    #
    # This builds the JSON-shaped Ruby Hash that Discord's webhook API
    # expects. Nesting a Hash inside an Array inside a Hash mirrors the
    # structure of the JSON Discord wants to receive.
    payload = {
      username: "StorageFinder",
      embeds: [
        {
          title:       "🏪 #{@message[:subject]}",
          description: @message[:text_body],
          color:       5763719,  # Green color in Discord's decimal format
          footer:      { text: "StorageFinder — #{Time.current.strftime("%B %d, %Y at %I:%M %p")}" }
          # `Time.current` gets the current time (Rails-aware, respecting
          # the app's configured time zone). `.strftime("%B %d, %Y at %I:%M %p")`
          # formats it as a human-readable string, e.g.
          # "July 22, 2026 at 03:45 PM" — each %-code is a formatting
          # placeholder (%B = full month name, %d = day, %Y = 4-digit
          # year, %I = 12-hour hour, %M = minute, %p = AM/PM).
        }
      ]
    }

    begin
      # `Faraday.new(webhook_url) do |f| ... end` builds an HTTP client
      # object configured to talk to the webhook_url. Faraday is a Ruby
      # gem/library for making HTTP requests. `f.options.open_timeout`/
      # `f.options.timeout` set how long to wait before giving up on
      # connecting or on the whole request, respectively — without these,
      # a slow/unresponsive server could hang this method indefinitely.
      conn = Faraday.new(webhook_url) do |f|
        f.options.open_timeout = 5   # Seconds to wait for the TCP connection
        f.options.timeout      = 10  # Seconds to wait for the full response
        # `f.adapter Faraday.default_adapter` tells Faraday which
        # underlying HTTP library to actually use to perform the request
        # (Faraday itself is a wrapper/interface over several possible
        # backends) — `default_adapter` uses whatever Faraday ships with
        # by default.
        f.adapter Faraday.default_adapter
      end
      # `end` closes the `Faraday.new(webhook_url) do |f|` configuration block.

      # Post as JSON manually — avoids needing faraday middleware adapters
      #
      # `conn.post do |req| ... end` performs an HTTP POST request using
      # the connection configured above.
      response = conn.post do |req|
        # Sets the request's Content-Type header so Discord's server knows
        # to interpret the request body as JSON.
        req.headers["Content-Type"] = "application/json"
        # `JSON.generate(payload)` converts the Ruby Hash built above into
        # an actual JSON-formatted String, which becomes the request body.
        req.body = JSON.generate(payload)
      end
      # `end` closes the `conn.post do |req|` block — `response` now holds
      # whatever Discord's server sent back.

      # `response.success?` is a Faraday helper that's true for HTTP
      # status codes in the 2xx range (200-299), meaning the request
      # succeeded from the server's point of view.
      if response.success?
        Rails.logger.info("[AlertDeliveryService] Discord alert sent successfully")
      else
        Rails.logger.error(
          "[AlertDeliveryService] Discord webhook returned error #{response.status}. " \
          "Response body: #{response.body}. " \
          "This usually means the webhook URL is invalid or the channel was deleted."
        )
      end
      # `end` closes the `if response.success?` / `else` block above.

    rescue Faraday::ConnectionFailed => e
      # Raised when the HTTP client couldn't even establish a network
      # connection to Discord's servers (DNS failure, no internet, etc.).
      Rails.logger.error(
        "[AlertDeliveryService] Could not connect to Discord webhook: #{e.message}. " \
        "Check your internet connection."
      )
    rescue Faraday::TimeoutError => e
      # Raised if the connection was made but the response didn't arrive
      # within the open_timeout/timeout limits configured above.
      Rails.logger.error(
        "[AlertDeliveryService] Discord webhook timed out: #{e.message}. " \
        "The webhook host may be slow or unreachable."
      )
    rescue => e
      # Catch-all for anything else unexpected.
      Rails.logger.error(
        "[AlertDeliveryService] Unexpected error sending Discord alert: #{e.class}: #{e.message}"
      )
    end
    # `end` closes the `begin` block that started the Discord-sending attempt.
  end
  # `end` closes the `def deliver_discord` method definition above.

  # ---------------------------------------------------------------------------
  # SMS DELIVERY (DISABLED — requires paid Twilio account)
  # ---------------------------------------------------------------------------
  def deliver_sms
    # This method is intentionally not fully implemented.
    # SMS requires a Twilio account (paid) which costs money.
    #
    # TO ENABLE SMS:
    #   1. Sign up at https://www.twilio.com (paid account required)
    #   2. Get an Account SID, Auth Token, and a Twilio phone number
    #   3. Add the 'twilio-ruby' gem to the Gemfile
    #   4. Run: bundle install
    #   5. Enter your Twilio credentials in Settings → SMS
    #   6. Remove the early return below and uncomment the Twilio code
    #
    # ESTIMATED COST: ~$1/month for a Twilio phone number + $0.0079/SMS
    # For occasional price alerts, this is very cheap, but it's not free.

    # Logs that SMS was skipped, so whoever reads the logs understands why
    # no text message went out even though this method ran (rather than
    # thinking something silently failed).
    Rails.logger.info(
      "[AlertDeliveryService] SMS alert skipped — SMS requires a paid Twilio account. " \
      "See comments in alert_delivery_service.rb for setup instructions."
    )
    # `nil` here is simply the method's return value (the last expression
    # evaluated) — it doesn't do anything on its own, it's just explicit
    # about "this method intentionally returns nothing meaningful."
    nil

    # --- UNCOMMENT THIS BLOCK AFTER TWILIO SETUP ---
    # Everything below this point is commented-out Ruby code (using `#` at
    # the start of each line) — it's inert on purpose: it's a template for
    # a developer to uncomment and adapt once real Twilio credentials are
    # available, rather than code that runs today.
    # account_sid = Setting.get("sms_twilio_account_sid")
    # auth_token  = Setting.get("sms_twilio_auth_token")
    # from_number = Setting.get("sms_from_number")
    # to_number   = @rule.sms_phone_number.presence || Setting.get("sms_to_number")
    #
    # if [account_sid, auth_token, from_number, to_number].any?(&:blank?)
    #   Rails.logger.error("[AlertDeliveryService] SMS settings incomplete")
    #   return
    # end
    #
    # client = Twilio::REST::Client.new(account_sid, auth_token)
    # client.messages.create(
    #   body: @message[:sms_body],
    #   from: from_number,
    #   to:   to_number
    # )
    # Rails.logger.info("[AlertDeliveryService] SMS alert sent to #{to_number}")
  end
  # `end` closes the `def deliver_sms` method definition above.
end
# `end` closes the `class AlertDeliveryService` definition that started at
# the top of this file.
