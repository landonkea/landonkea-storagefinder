# =============================================================================
# SETTINGS CONTROLLER
# =============================================================================
# Handles the Settings page where users configure email, Discord, schedules, etc.
# =============================================================================

require "ostruct"

class SettingsController < ApplicationController
  # ---------------------------------------------------------------------------
  # INDEX — show all settings grouped by category
  # ---------------------------------------------------------------------------
  def index
    @page_title = "Settings — StorageFinder"

    # Load settings grouped by category for the tabbed settings UI
    @settings_by_category = Setting.all.group_by(&:category)

    # Load alert rules for the alerts section
    @alert_rules = AlertRule.all.order(:name)
  end

  # ---------------------------------------------------------------------------
  # UPDATE — save settings (submitted from the settings form)
  # ---------------------------------------------------------------------------
  def update
    # params[:settings] is a hash of { key => value } from the form. Settings
    # are a dynamic key-value store (not fixed model columns), so the
    # permitted list has to be built from what's actually in the table rather
    # than named individually — but it's still an explicit allowlist, not a
    # blanket permit!, and each "<key>_unchecked" companion field (see the
    # boolean-checkbox handling below) needs the same allowance.
    known_keys    = Setting.pluck(:key)
    allowed_keys  = known_keys + known_keys.map { |key| "#{key}_unchecked" }
    raw_params    = params.require(:settings).permit(*allowed_keys).to_h

    # -------------------------------------------------------------------------
    # BOOLEAN FIELD HANDLING
    # -------------------------------------------------------------------------
    # HTML checkboxes have a quirk: if a checkbox is UNCHECKED, the browser
    # sends nothing for that field. So we use a companion hidden field with
    # a "_unchecked" suffix (value="false") as a fallback.
    #
    # Example: email_enabled checkbox
    #   Checked:   params[:settings] = { "email_enabled" => "true",  "email_enabled_unchecked" => "false" }
    #   Unchecked: params[:settings] = { "email_enabled_unchecked" => "false" }
    #
    # We merge the _unchecked values first, then let real values override them.
    # Then we strip out all keys ending in "_unchecked".
    # -------------------------------------------------------------------------

    # Step 1: Build a hash of just the unchecked fallback values
    # e.g. { "email_enabled" => "false" } from { "email_enabled_unchecked" => "false" }
    unchecked_fallbacks = {}
    raw_params.each do |key, value|
      if key.end_with?("_unchecked")
        real_key = key.sub(/_unchecked$/, "")
        unchecked_fallbacks[real_key] = value
      end
    end

    # Step 2: Start with unchecked fallbacks, then override with any actual values
    # This ensures unchecked checkboxes get "false" rather than being ignored
    merged = unchecked_fallbacks.merge(
      raw_params.reject { |key, _| key.end_with?("_unchecked") }
    )

    # Step 3: Save each setting
    saved_count = 0
    errors      = []

    merged.each do |key, value|
      begin
        # Verify this is a known setting key before saving
        # This prevents accidental creation of rogue settings from form tampering
        setting = Setting.find_by(key: key)
        if setting.nil?
          Rails.logger.warn("[SettingsController] Ignoring unknown setting key '#{key}'")
          next
        end

        # Password fields render blank (see settings/index.html.erb) so the
        # current value never appears in the page HTML. That means an
        # untouched password field submits "" on every save — skip it so we
        # don't wipe out the stored value every time the form is submitted.
        next if setting.input_type == "password" && value.blank?

        Setting.set(key, value)
        saved_count += 1
      rescue => e
        errors << "Could not save '#{key}': #{e.message}"
        Rails.logger.error("[SettingsController] Failed to save setting '#{key}': #{e.message}")
      end
    end

    if errors.empty?
      flash[:notice] = "#{saved_count} setting#{"s" if saved_count != 1} saved."
    else
      flash[:alert] = "Saved #{saved_count} settings. #{errors.length} failed: #{errors.join("; ")}"
    end

    redirect_to settings_path
  end

  # ---------------------------------------------------------------------------
  # TEST EMAIL — send a test email to verify SMTP settings
  # ---------------------------------------------------------------------------
  def test_email
    to_address = Setting.get("email_to_address")

    if to_address.blank?
      render json: { success: false, message: "No recipient email address configured in settings." }
      return
    end

    # Build a minimal rule-like object for the delivery service
    # (AlertDeliveryService normally takes an AlertRule, but we need a standalone test)
    fake_rule = OpenStruct.new(
      email_enabled?:      true,
      discord_enabled?:    false,
      sms_enabled?:        false,
      email_address:       to_address,
      discord_webhook_url: nil,
      sms_phone_number:    nil,
      name:                "Test Alert"
    )

    message = {
      subject:   "StorageFinder Test — email is working!",
      text_body: "This is a test email from StorageFinder. Your email alerts are configured correctly.",
      html_body: "<h2>&#10003; StorageFinder Test Email</h2><p>Your email alerts are configured correctly.</p>",
      sms_body:  nil
    }

    begin
      AlertDeliveryService.deliver(fake_rule, message)
      render json: { success: true, message: "Test email sent to #{to_address}. Check your inbox." }
    rescue => e
      render json: { success: false, message: "Failed to send test email: #{e.message}" }
    end
  end

  # ---------------------------------------------------------------------------
  # TEST DISCORD — send a test message to verify the Discord webhook
  # ---------------------------------------------------------------------------
  def test_discord
    webhook_url = Setting.get("discord_webhook_url")

    if webhook_url.blank?
      render json: { success: false, message: "No Discord webhook URL configured in settings." }
      return
    end

    begin
      conn = Faraday.new(webhook_url) do |f|
        f.options.open_timeout = 5   # Seconds to wait for the TCP connection
        f.options.timeout      = 10  # Seconds to wait for the full response
        f.adapter Faraday.default_adapter
      end

      response = conn.post do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate({
        username: "StorageFinder",
        content:  "\u2713 StorageFinder test message \u2014 Discord alerts are configured correctly!"
        })
      end

      if response.success?
        render json: { success: true, message: "Test message sent to Discord successfully." }
      else
        render json: {
          success: false,
          message: "Discord returned error #{response.status}. " \
                   "This usually means the webhook URL is invalid or the channel was deleted. " \
                   "Check your webhook URL in Discord channel settings."
        }
      end

    rescue Faraday::ConnectionFailed => e
      render json: { success: false, message: "Could not connect to Discord: #{e.message}" }
    rescue Faraday::TimeoutError => e
      render json: { success: false, message: "Discord webhook timed out: #{e.message}" }
    rescue => e
      render json: { success: false, message: "Unexpected error: #{e.message}" }
    end
  end
end
