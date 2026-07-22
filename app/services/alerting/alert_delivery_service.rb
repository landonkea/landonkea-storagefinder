# =============================================================================
# ALERT DELIVERY SERVICE
# =============================================================================
# Sends alert notifications via Email and/or Discord.
# SMS is wired up structurally but disabled — it requires a paid Twilio account.
# =============================================================================

class AlertDeliveryService
  # Deliver an alert via all channels configured on the rule
  def self.deliver(rule, message)
    new(rule, message).deliver
  end

  def initialize(rule, message)
    @rule    = rule
    @message = message
  end

  def deliver
    deliver_email   if @rule.email_enabled?   && Setting.enabled?("email_enabled")
    deliver_discord if @rule.discord_enabled? && Setting.enabled?("discord_enabled")
    deliver_sms     if @rule.sms_enabled?     && Setting.enabled?("sms_enabled")
  end

  private

  # ---------------------------------------------------------------------------
  # EMAIL DELIVERY
  # ---------------------------------------------------------------------------
  def deliver_email
    smtp_host     = Setting.get("email_smtp_host")
    smtp_port     = Setting.get("email_smtp_port", default: 587).to_i
    smtp_username = Setting.get("email_smtp_username")
    smtp_password = Setting.get("email_smtp_password")
    from_address  = Setting.get("email_from_address") || smtp_username
    to_address    = @rule.email_address.presence || Setting.get("email_to_address")

    # Validate we have what we need before trying
    if smtp_host.blank? || smtp_username.blank? || smtp_password.blank?
      Rails.logger.error(
        "[AlertDeliveryService] Cannot send email alert — SMTP settings are incomplete. " \
        "Please configure email settings in the Settings page."
      )
      return
    end

    if to_address.blank?
      Rails.logger.error(
        "[AlertDeliveryService] Cannot send email alert — no recipient address configured. " \
        "Set 'Send alerts to' in Settings or specify an email on the alert rule."
      )
      return
    end

    begin
      mail = Mail.new do
        from    from_address
        to      to_address
        subject "StorageFinder Alert: #{@message[:subject]}"

        text_part do
          body @message[:text_body]
        end

        html_part do
          content_type "text/html; charset=UTF-8"
          body @message[:html_body]
        end
      end

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

      mail.deliver!
      Rails.logger.info("[AlertDeliveryService] Email alert sent to #{to_address}")

    rescue Net::SMTPAuthenticationError => e
      Rails.logger.error(
        "[AlertDeliveryService] SMTP authentication failed. " \
        "Check your username and password (or app password for Gmail). " \
        "Error: #{e.message}"
      )
    rescue Net::SMTPServerBusy, Net::SMTPFatalError => e
      Rails.logger.error(
        "[AlertDeliveryService] SMTP server error sending email: #{e.message}"
      )
    rescue => e
      Rails.logger.error(
        "[AlertDeliveryService] Unexpected error sending email: #{e.class}: #{e.message}"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # DISCORD DELIVERY
  # ---------------------------------------------------------------------------
  def deliver_discord
    # Use the rule's specific webhook URL if set, otherwise fall back to the global one
    webhook_url = @rule.discord_webhook_url.presence || Setting.get("discord_webhook_url")

    if webhook_url.blank?
      Rails.logger.error(
        "[AlertDeliveryService] Cannot send Discord alert — no webhook URL configured. " \
        "Set a Discord webhook URL in Settings or on the alert rule."
      )
      return
    end

    # Discord webhook payload format
    # The "embeds" array creates a rich formatted card in Discord
    payload = {
      username: "StorageFinder",
      embeds: [
        {
          title:       "🏪 #{@message[:subject]}",
          description: @message[:text_body],
          color:       5763719,  # Green color in Discord's decimal format
          footer:      { text: "StorageFinder — #{Time.current.strftime("%B %d, %Y at %I:%M %p")}" }
        }
      ]
    }

    begin
      conn = Faraday.new(webhook_url) do |f|
        f.options.open_timeout = 5   # Seconds to wait for the TCP connection
        f.options.timeout      = 10  # Seconds to wait for the full response
        f.adapter Faraday.default_adapter
      end

      # Post as JSON manually — avoids needing faraday middleware adapters
      response = conn.post do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
      end

      if response.success?
        Rails.logger.info("[AlertDeliveryService] Discord alert sent successfully")
      else
        Rails.logger.error(
          "[AlertDeliveryService] Discord webhook returned error #{response.status}. " \
          "Response body: #{response.body}. " \
          "This usually means the webhook URL is invalid or the channel was deleted."
        )
      end

    rescue Faraday::ConnectionFailed => e
      Rails.logger.error(
        "[AlertDeliveryService] Could not connect to Discord webhook: #{e.message}. " \
        "Check your internet connection."
      )
    rescue Faraday::TimeoutError => e
      Rails.logger.error(
        "[AlertDeliveryService] Discord webhook timed out: #{e.message}. " \
        "The webhook host may be slow or unreachable."
      )
    rescue => e
      Rails.logger.error(
        "[AlertDeliveryService] Unexpected error sending Discord alert: #{e.class}: #{e.message}"
      )
    end
  end

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

    Rails.logger.info(
      "[AlertDeliveryService] SMS alert skipped — SMS requires a paid Twilio account. " \
      "See comments in alert_delivery_service.rb for setup instructions."
    )
    nil

    # --- UNCOMMENT THIS BLOCK AFTER TWILIO SETUP ---
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
end
