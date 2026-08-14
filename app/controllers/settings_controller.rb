# =============================================================================
# SETTINGS CONTROLLER
# =============================================================================
# Handles the Settings page where users configure email, Discord, schedules, etc.
# =============================================================================

# `require "ostruct"` loads Ruby's standard-library `OpenStruct` class
# (used further down in `test_email`), like the `require "csv"` seen in
# ExportsController, Ruby's standard library isn't automatically loaded
# everywhere, so files that use it must explicitly require it. This is a
# top-level `require`, meaning it runs once when this file is first loaded
# by Rails, before the class definition below even exists yet.
require "ostruct"

# `class SettingsController < ApplicationController`, see
# app/controllers/application_controller.rb for what "controller" and
# "inherits from" mean.
class SettingsController < ApplicationController
  # ---------------------------------------------------------------------------
  # INDEX, show all settings grouped by category
  # ---------------------------------------------------------------------------
  # `index` is the conventional action for the settings page itself (GET
  # /settings).
  def index
    @page_title = "Settings, StorageFinder"

    # Load settings grouped by category for the tabbed settings UI
    # `Setting.all` fetches every row from the settings table.
    # `.group_by(&:category)` is Ruby's Enumerable#group_by, using the
    # `&:category` shorthand (equivalent to `{ |s| s.category }`) to bucket
    # every Setting record into a hash keyed by its `category` value, e.g.
    # { "email" => [...], "discord" => [...] }, so the view can render one
    # tab per category.
    @settings_by_category = Setting.all.group_by(&:category)

    # Load alert rules for the alerts section
    @alert_rules = AlertRule.all.order(:name)
  end
  # `end` closes the `def index` action definition opened above.

  # ---------------------------------------------------------------------------
  # UPDATE, save settings (submitted from the settings form)
  # ---------------------------------------------------------------------------
  # `update` runs when the settings form is submitted (PATCH/POST
  # /settings), this handles every settings category/field in one shared
  # action, since Settings are a flexible key-value store rather than fixed
  # model columns.
  def update
    # params[:settings] is a hash of { key => value } from the form. Settings
    # are a dynamic key-value store (not fixed model columns), so the
    # permitted list has to be built from what's actually in the table rather
    # than named individually, but it's still an explicit allowlist, not a
    # blanket permit!, and each "<key>_unchecked" companion field (see the
    # boolean-checkbox handling below) needs the same allowance.
    # `Setting.pluck(:key)` runs an efficient database query that returns
    # ONLY the `key` column's values (as a plain Ruby array of strings),
    # rather than loading full Setting objects, faster when only one
    # column is needed.
    known_keys    = Setting.pluck(:key)
    # Builds a combined allowlist covering both the real setting keys AND
    # their "_unchecked" companion field names (explained further below).
    # `known_keys.map { |key| "#{key}_unchecked" }` transforms each key
    # string into a new string with "_unchecked" appended, via string
    # interpolation; `+` concatenates the two arrays together.
    allowed_keys  = known_keys + known_keys.map { |key| "#{key}_unchecked" }
    # `params.require(:settings)` asserts the request must include a
    # top-level `:settings` key (see AlertRulesController#alert_rule_params
    # for the same `.require`/`.permit` "strong parameters" pattern).
    # `.permit(*allowed_keys)` filters it down to only the allowed field
    # names, the `*` here is Ruby's "splat" operator, which expands the
    # `allowed_keys` ARRAY into individual arguments, since `.permit`
    # expects each allowed key as a separate argument rather than one
    # array argument. `.to_h` converts the resulting (still Rails-specific)
    # "parameters" object into a plain Ruby Hash for easier manipulation
    # below.
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
    # `{}` is an empty hash literal, starting point to be filled in below.
    unchecked_fallbacks = {}
    # `raw_params.each do |key, value| ... end` iterates over every
    # key/value pair in the hash; unlike `.map`, `.each` here is used for
    # its side effect (building up `unchecked_fallbacks`) rather than to
    # produce a new collection.
    raw_params.each do |key, value|
      # `.end_with?("_unchecked")` checks whether this particular key is
      # one of the companion hidden-field keys rather than a real setting.
      if key.end_with?("_unchecked")
        # `.sub(/_unchecked$/, "")` removes the "_unchecked" suffix using a
        # regular expression (`/_unchecked$/`, the `$` means "only match
        # at the end of the string"), turning e.g. "email_enabled_unchecked"
        # back into "email_enabled", `.sub` replaces just the FIRST match
        # (there's only one match possible here anyway) with the given
        # replacement, an empty string, i.e. deleting it.
        real_key = key.sub(/_unchecked$/, "")
        # Records this fallback value under the real (un-suffixed) key
        # name in the `unchecked_fallbacks` hash being built up.
        unchecked_fallbacks[real_key] = value
      end
      # `end` closes the `if key.end_with?("_unchecked")` block above.
    end
    # `end` closes the `raw_params.each do |key, value| ... end` loop above.

    # Step 2: Start with unchecked fallbacks, then override with any actual values
    # This ensures unchecked checkboxes get "false" rather than being ignored
    # `.merge(...)` combines two hashes: it starts with
    # `unchecked_fallbacks`, then layers the second hash's keys on top,
    # with the second hash's values winning on any key that appears in
    # both, so a real submitted value (e.g. "email_enabled" => "true")
    # overrides its own fallback ("email_enabled" => "false" from the
    # companion field), while fields that truly have no real value keep
    # their "false" fallback.
    merged = unchecked_fallbacks.merge(
      # `raw_params.reject { |key, _| key.end_with?("_unchecked") }` builds
      # a copy of raw_params with all "_unchecked"-suffixed keys removed,
      # `.reject` keeps only the pairs where the block returns FALSE
      # (opposite of `.select`/`.filter`). The block parameter `_` (a bare
      # underscore) is Ruby convention for "an argument I'm intentionally
      # not using", here, the value half of each pair isn't needed to
      # decide whether to reject it.
      raw_params.reject { |key, _| key.end_with?("_unchecked") }
    )
    # `)` closes the `.merge(...)` call opened two lines above.

    # Step 3: Save each setting
    saved_count = 0
    # `[]` is an empty array literal, will collect error message strings
    # for any settings that fail to save below.
    errors      = []

    # `merged.each do |key, value| ... end`, final pass over the cleaned-up
    # key/value pairs, actually persisting each one to the database.
    merged.each do |key, value|
      # `begin ... rescue ... end` is Ruby's general error-handling block,
      # unlike the method-level `rescue` clauses seen in other controllers
      # in this app, this `begin` is used INSIDE the loop so that ONE
      # setting failing to save doesn't stop the rest from being attempted;
      # a method-level rescue would abort the whole loop on the first error.
      begin
        # Verify this is a known setting key before saving
        # This prevents accidental creation of rogue settings from form tampering
        # `Setting.find_by(key: key)` looks up a Setting row by its `key`
        # column, returning nil (rather than raising an error, unlike
        # `.find`) if no match exists, appropriate here since "not found"
        # is an expected, handled case, not an exceptional one.
        setting = Setting.find_by(key: key)
        # `.nil?` checks specifically for Ruby's `nil` value.
        if setting.nil?
          Rails.logger.warn("[SettingsController] Ignoring unknown setting key '#{key}'")
          # `next` skips the rest of THIS iteration of the enclosing
          # `.each` loop and moves on to the next key/value pair, it does
          # NOT exit the whole loop (that would be `break`), just this one
          # pass.
          next
        end
        # `end` closes the `if setting.nil?` block above.

        # Password fields render blank (see settings/index.html.erb) so the
        # current value never appears in the page HTML. That means an
        # untouched password field submits "" on every save, skip it so we
        # don't wipe out the stored value every time the form is submitted.
        # `next if ...` is a trailing conditional form of `next`, read as
        # "skip this iteration if the condition after `if` is true."
        # `setting.input_type == "password"` checks this setting's declared
        # field type; `value.blank?` (Rails helper, true for nil/"" /
        # whitespace-only) checks whether nothing meaningful was submitted.
        next if setting.input_type == "password" && value.blank?

        # `Setting.set(key, value)` is a custom class method that writes/
        # updates this key's stored value in the database.
        Setting.set(key, value)
        saved_count += 1
      # `rescue => e` here catches any error raised while processing THIS
      # one key/value pair, scoped to the `begin` block just above, not
      # the whole method, thanks to `begin...rescue...end`.
      rescue => e
        # `<<` here is Array's "append" operator, adding one more error
        # string onto the end of the `errors` array.
        errors << "Could not save '#{key}': #{e.message}"
        Rails.logger.error("[SettingsController] Failed to save setting '#{key}': #{e.message}")
      end
      # `end` closes the `begin ... rescue ... end` block for this
      # iteration.
    end
    # `end` closes the `merged.each do |key, value| ... end` loop above.

    # `.empty?` checks whether the errors array has zero elements, i.e.
    # every setting saved successfully.
    if errors.empty?
      # `"s" if saved_count != 1`, trailing `if` modifier: only include
      # the plural "s" when saved_count is NOT exactly 1, for correct
      # grammar ("1 setting saved." vs "3 settings saved.").
      flash[:notice] = "#{saved_count} setting#{"s" if saved_count != 1} saved."
    else
      # `.join("; ")` concatenates every error message in the array into
      # one semicolon-separated string for display.
      flash[:alert] = "Saved #{saved_count} settings. #{errors.length} failed: #{errors.join("; ")}"
    end
    # `end` closes the `if errors.empty? ... else ... end` block above.

    redirect_to settings_path
  end
  # `end` closes the `def update` action definition opened above.

  # ---------------------------------------------------------------------------
  # TEST EMAIL, send a test email to verify SMTP settings
  # ---------------------------------------------------------------------------
  # `test_email` is a custom action (needs an explicit route), triggered by
  # a "Send Test Email" button on the settings page, letting the user
  # verify their email configuration works without waiting for a real
  # price alert.
  def test_email
    # `Setting.get(...)` (see DashboardController for the same method, used
    # there with a `default:` fallback) reads the currently configured
    # "send test/alert emails to this address" setting.
    to_address = Setting.get("email_to_address")

    # `.blank?`, see earlier note; true if nothing (or only whitespace)
    # was ever configured for this setting.
    if to_address.blank?
      render json: { success: false, message: "No recipient email address configured in settings." }
      return
    end
    # `end` closes the `if to_address.blank?` block above.

    # Build a minimal rule-like object for the delivery service
    # (AlertDeliveryService normally takes an AlertRule, but we need a standalone test)
    # `OpenStruct.new(...)` (from the `require "ostruct"` at the top of this
    # file) builds an object on the fly that responds to whatever method
    # names are given as hash keys below, e.g. `fake_rule.email_enabled?`
    # will return `true`. This is used here to mimic the shape of a real
    # AlertRule database record (which has these same methods) without
    # actually needing one saved in the database, since this is just a
    # one-off test send. Note the hash keys below include trailing `?`
    # characters (e.g. `email_enabled?:`), that's allowed because Ruby
    # method/symbol names can end in `?`, and OpenStruct turns each key
    # directly into a same-named method.
    fake_rule = OpenStruct.new(
      email_enabled?:      true,
      discord_enabled?:    false,
      sms_enabled?:        false,
      email_address:       to_address,
      discord_webhook_url: nil,
      sms_phone_number:    nil,
      name:                "Test Alert"
    )
    # `)` closes the `OpenStruct.new(...)` call opened above.

    # Builds a plain hash describing the test message's content, the
    # shape AlertDeliveryService.deliver expects (subject/body text for
    # each channel it might send through).
    message = {
      subject:   "StorageFinder Test, email is working!",
      text_body: "This is a test email from StorageFinder. Your email alerts are configured correctly.",
      # `"<h2>&#10003; ...`, an HTML string containing a checkmark
      # character written as an HTML numeric entity (`&#10003;`), used for
      # the HTML-formatted version of the email body.
      html_body: "<h2>&#10003; StorageFinder Test Email</h2><p>Your email alerts are configured correctly.</p>",
      # `nil` here, no SMS body needed since `sms_enabled?` on the fake
      # rule above is false.
      sms_body:  nil
    }
    # `}` closes the `message = { ... }` hash literal above.

    # `begin ... rescue ... end` wraps just the actual delivery attempt,
    # since sending mail can fail for many external reasons (bad SMTP
    # settings, network issues) that shouldn't crash this action, instead
    # they're reported back as JSON.
    begin
      # `AlertDeliveryService.deliver(fake_rule, message)` is a custom
      # service class (not shown in this file) that actually sends the
      # email (and would send Discord/SMS too, for a real alert rule with
      # those channels enabled, here they're forced off via `fake_rule`).
      AlertDeliveryService.deliver(fake_rule, message)
      render json: { success: true, message: "Test email sent to #{to_address}. Check your inbox." }
    rescue => e
      render json: { success: false, message: "Failed to send test email: #{e.message}" }
    end
    # `end` closes the `begin ... rescue ... end` block above.
  end
  # `end` closes the `def test_email` action definition opened above.

  # ---------------------------------------------------------------------------
  # TEST DISCORD, send a test message to verify the Discord webhook
  # ---------------------------------------------------------------------------
  # `test_discord` mirrors `test_email` above, but for Discord notifications
  #, Discord webhooks are simple HTTP POST endpoints, so this sends a real
  # HTTP request directly rather than going through AlertDeliveryService.
  def test_discord
    webhook_url = Setting.get("discord_webhook_url")

    if webhook_url.blank?
      render json: { success: false, message: "No Discord webhook URL configured in settings." }
      return
    end
    # `end` closes the `if webhook_url.blank?` block above.

    begin
      # `Faraday.new(webhook_url) do |f| ... end` builds an HTTP client
      # object configured to talk to `webhook_url`. Faraday is a Ruby gem
      # (third-party library) for making HTTP requests. The block
      # configures connection options on the `f` (connection) object
      # before it's used.
      conn = Faraday.new(webhook_url) do |f|
        # Sets how many seconds to wait for the initial TCP connection to
        # be established before giving up.
        f.options.open_timeout = 5   # Seconds to wait for the TCP connection
        # Sets how many seconds to wait for the ENTIRE request/response
        # round-trip before giving up.
        f.options.timeout      = 10  # Seconds to wait for the full response
        # `f.adapter Faraday.default_adapter` selects which underlying HTTP
        # library Faraday should use to actually perform requests
        # (Faraday itself is a wrapper/interface over several possible
        # HTTP libraries; `.default_adapter` picks whichever one is
        # available/configured by default).
        f.adapter Faraday.default_adapter
      end
      # `end` closes the `Faraday.new(webhook_url) do |f| ... end` block.

      # `conn.post do |req| ... end` sends an HTTP POST request using the
      # connection configured above, yielding a `req` (request) object to
      # the block so headers/body can be set before it's actually sent.
      response = conn.post do |req|
        # Tells Discord's webhook endpoint the request body is JSON.
        req.headers["Content-Type"] = "application/json"
        # `JSON.generate({...})` converts a Ruby hash into a JSON-formatted
        # string, the actual text sent as the request body. Discord's
        # webhook API expects a JSON body with (at least) a `content`
        # field for the message text; `username:` overrides the display
        # name Discord shows for this webhook message.
        req.body = JSON.generate({
        username: "StorageFinder",
        # `✓` is a Unicode escape sequence inside a Ruby string
        # literal, it inserts the checkmark character (✓) by its Unicode
        # code point number, rather than typing the character directly;
        # `—` further down is an em-dash (—) the same way.
        content:  "✓ StorageFinder test message, Discord alerts are configured correctly!"
        })
        # `)` closes the `JSON.generate({...})` call.
      end
      # `end` closes the `conn.post do |req| ... end` block above.

      # `.success?` is a Faraday response method, true for any HTTP 2xx
      # status code, indicating Discord accepted the message.
      if response.success?
        render json: { success: true, message: "Test message sent to Discord successfully." }
      else
        render json: {
          success: false,
          # `\` at the end of a line inside a string is Ruby's line-
          # continuation operator FOR STRING LITERALS, it joins this
          # string with the one on the next line into a single combined
          # string, letting a long message be split across source lines
          # without an actual line break appearing in the final text.
          # `response.status` reads the numeric HTTP status code Discord
          # returned (e.g. 404, 401) for troubleshooting.
          message: "Discord returned error #{response.status}. " \
                   "This usually means the webhook URL is invalid or the channel was deleted. " \
                   "Check your webhook URL in Discord channel settings."
        }
      end
    # `end` closes the `if response.success? ... else ... end` block above.

    # Three specific `rescue` clauses, checked top-to-bottom, Ruby tries
    # each `rescue ExceptionClass` in order and runs the first one whose
    # class matches the actual error raised; if none of the specific ones
    # match, the final bare `rescue` below catches anything else
    # (StandardError and subclasses).
    rescue Faraday::ConnectionFailed => e
      # Raised when the network connection itself could not be established
      # (e.g. DNS failure, connection refused), different from Discord
      # returning an error status, which is handled by `response.success?`
      # above instead.
      render json: { success: false, message: "Could not connect to Discord: #{e.message}" }
    rescue Faraday::TimeoutError => e
      # Raised if the request took longer than the `open_timeout`/`timeout`
      # values configured above.
      render json: { success: false, message: "Discord webhook timed out: #{e.message}" }
    rescue => e
      # Catches anything else unexpected not covered by the two specific
      # rescues above.
      render json: { success: false, message: "Unexpected error: #{e.message}" }
    end
    # `end` closes the `begin ... rescue ... end` block opened above.
  end
  # `end` closes the `def test_discord` action definition opened above.
end
# `end` closes the `class SettingsController` definition opened at the top
# of the file.
