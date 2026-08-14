# =============================================================================
# DATABASE SEEDS
# =============================================================================
# Seeds are default data inserted into the database when you run:
#   rails db:seed
#
# This file sets up the default settings that appear on the Settings page.
# It uses find_or_create_by so running seeds twice doesn't create duplicates.
# =============================================================================

# `puts` prints a line of text to the terminal/console, this just prints a
# status message so whoever runs `rails db:seed` sees the script is working.
puts "Seeding default settings..."

# Helper method to create a setting if it doesn't already exist
# `def seed_setting(key:, value: nil, category:, label:, input_type: "text")`
# defines a new Ruby method named `seed_setting`. Every parameter here uses
# KEYWORD ARGUMENTS (the `name:` syntax) rather than plain positional ones,
# meaning every call below must pass arguments as `key: "...", category:
# "..."` etc. by name, in any order, instead of relying on position. `key:`,
# `category:`, and `label:` have no default given, so they are REQUIRED,
# Ruby raises an error if a caller omits them. `value: nil` and `input_type:
# "text"` provide DEFAULT values, making those two arguments optional, if a
# caller doesn't pass them, `value` becomes `nil` and `input_type` becomes
# the string `"text"` automatically. The matching `end` a few lines down
# closes this method definition.
def seed_setting(key:, value: nil, category:, label:, input_type: "text")
  # `Setting.find_or_create_by(key: key)` is an ActiveRecord method: it
  # first searches the "settings" database table for an existing row whose
  # "key" column matches the `key` argument passed in; if one is found, it's
  # returned as-is (nothing new is created, and the `do |s| ... end` block
  # below is SKIPPED). If no matching row exists, a brand-new Setting row is
  # created and the block below runs to fill in its other columns before
  # saving. This is exactly what makes re-running `rails db:seed` safe: a
  # second run finds the settings already exist and leaves them untouched,
  # instead of creating duplicate rows. `do |s|` opens the block, with `s`
  # representing the new (not-yet-saved) Setting record. The matching `end`
  # two lines down closes this block.
  Setting.find_or_create_by(key: key) do |s|
    # Sets the new row's "value" column from the `value` argument. The
    # extra spaces are just manual alignment so the `=` signs line up
    # visually; they don't change what the code does.
    s.value      = value
    # Sets the new row's "category" column from the `category` argument.
    s.category   = category
    # Sets the new row's "label" column from the `label` argument.
    s.label      = label
    # Sets the new row's "input_type" column from the `input_type`
    # argument (or its "text" default, if the caller didn't override it).
    s.input_type = input_type
  end
  # This `end` closes the `Setting.find_or_create_by(key: key) do |s|`
  # block above.
  # Prints a confirmation line to the console for this one setting, so the
  # person running `rails db:seed` can see progress. `#{key}` is Ruby STRING
  # INTERPOLATION, inside a double-quoted string, `#{...}` is replaced with
  # the result of evaluating the Ruby expression inside it (here, just the
  # `key` argument's value) before printing.
  puts "  ✓ Setting: #{key}"
end
# This `end` closes the `def seed_setting(...)` method definition opened
# above. From here on, the file just calls `seed_setting` repeatedly with
# different arguments to populate every default setting.

# -------------------------------------------------------------------------
# CRAWL SETTINGS
# -------------------------------------------------------------------------
# Calls the `seed_setting` method defined above, passing each keyword
# argument on its own line (Ruby allows a method call's arguments to be
# spread across multiple lines like this, as long as the parentheses aren't
# closed until the last one). This creates/confirms a setting controlling
# the default search radius, shown on the Settings page as a number input.
seed_setting(
  key:        "crawl_default_radius_miles",
  value:      "100",
  category:   "crawl",
  label:      "Default search radius (miles)",
  input_type: "number"
)

# Setting controlling how many times a failed page load is retried during a
# crawl, shown as a number input.
seed_setting(
  key:        "crawl_max_retries",
  value:      "3",
  category:   "crawl",
  label:      "Max retries per page",
  input_type: "number"
)

# Setting controlling the delay (in milliseconds) between requests during a
# crawl, a larger delay is gentler on slower hardware/network connections.
# Shown as a number input.
seed_setting(
  key:        "crawl_delay_between_requests_ms",
  value:      "2000",
  category:   "crawl",
  label:      "Delay between requests (milliseconds), increase on slow hardware",
  input_type: "number"
)

# Setting controlling whether the crawler's browser runs "headless" (with
# no visible window) or visibly on-screen. Shown as a boolean (on/off)
# input.
seed_setting(
  key:        "crawl_headless",
  value:      "true",
  category:   "crawl",
  label:      "Run browser in headless mode (invisible)",
  input_type: "boolean"
)

# Setting controlling how many storage companies can be crawled at the same
# time, lowering this reduces CPU/RAM usage at the cost of a slower overall
# crawl. Shown as a number input.
seed_setting(
  key:        "crawl_parallel_companies",
  value:      "2",
  category:   "crawl",
  label:      "Max companies to crawl simultaneously (lower = less CPU/RAM usage)",
  input_type: "number"
)

# -------------------------------------------------------------------------
# SCHEDULE SETTINGS
# -------------------------------------------------------------------------
# Setting controlling whether automatic scheduled crawls are turned on at
# all. Shown as a boolean input, and defaults to "false" (off), a novice
# installing this app for the first time won't have crawls running
# automatically until they explicitly opt in.
seed_setting(
  key:        "schedule_enabled",
  value:      "false",
  category:   "schedule",
  label:      "Enable scheduled automatic crawls",
  input_type: "boolean"
)

# Setting holding the schedule itself, written in "cron format", a
# standard, compact way of expressing recurring times used by many
# scheduling tools (five space-separated fields for minute, hour, day-of-
# month, month, and day-of-week; `*` means "every"). The default value
# "0 6 * * *" means "at minute 0 of hour 6, every day", i.e. 6:00 AM daily.
# Shown as a plain text input.
seed_setting(
  key:        "schedule_cron",
  value:      "0 6 * * *",
  category:   "schedule",
  label:      "Schedule (cron format), default is every day at 6:00 AM",
  input_type: "text"
)
# NOTE: unlike most other settings here, this one's `value:` is a literal
# cron expression rather than a simple number/boolean/blank string, worth
# knowing if you're adding a UI to edit it later, since it needs validating
# as valid cron syntax rather than treated as free text.

# Setting holding which city to search on a scheduled crawl. `value: ""` is
# an empty string, meaning it starts blank, the label explains that a
# blank value falls back to whatever city was last searched manually.
# Shown as a plain text input.
seed_setting(
  key:        "schedule_city",
  value:      "",
  category:   "schedule",
  label:      "City to search on schedule (leave blank to use last manual search)",
  input_type: "text"
)

# Setting holding the search radius (in miles) to use for scheduled crawls.
# Shown as a number input.
seed_setting(
  key:        "schedule_radius_miles",
  value:      "100",
  category:   "schedule",
  label:      "Radius to use on scheduled crawl (miles)",
  input_type: "number"
)

# -------------------------------------------------------------------------
# EMAIL ALERT SETTINGS
# -------------------------------------------------------------------------
# Setting controlling whether email alerts are enabled at all. Defaults to
# "false" (off), shown as a boolean input.
seed_setting(
  key:        "email_enabled",
  value:      "false",
  category:   "email",
  label:      "Enable email alerts",
  input_type: "boolean"
)

# Setting holding the outgoing mail server hostname to connect to (SMTP,
# Simple Mail Transfer Protocol, is the standard protocol used to send
# email). Defaults to Gmail's server. Shown as a plain text input.
seed_setting(
  key:        "email_smtp_host",
  value:      "smtp.gmail.com",
  category:   "email",
  label:      "SMTP server hostname",
  input_type: "text"
)

# Setting holding the network port number to connect to on the SMTP server.
# Defaults to 587, the standard port for encrypted (TLS) mail submission.
# Shown as a number input.
seed_setting(
  key:        "email_smtp_port",
  value:      "587",
  category:   "email",
  label:      "SMTP port (587 for Gmail TLS, 465 for SSL)",
  input_type: "number"
)

# Setting holding the username used to log into the SMTP server (typically
# the sender's Gmail address). Starts blank. Shown as a plain text input.
seed_setting(
  key:        "email_smtp_username",
  value:      "",
  category:   "email",
  label:      "SMTP username (your Gmail address)",
  input_type: "text"
)

# Setting holding the password (or app-specific password) used to log into
# the SMTP server. Starts blank. `input_type: "password"` tells the
# Settings page to render this as a masked password field rather than
# plain text, so it isn't shown on-screen while typing, that only affects
# how the HTML input LOOKS, it doesn't encrypt anything by itself. The
# actual encryption-at-rest is handled separately, at the model level: see
# `encrypts :value` in app/models/setting.rb, which transparently encrypts
# EVERY setting's `value` column (not just password-typed ones) before it's
# written to the database, so this SMTP password is not stored as plain
# text.
seed_setting(
  key:        "email_smtp_password",
  value:      "",
  category:   "email",
  label:      "SMTP password or app password",
  input_type: "password"
)

# Setting holding the "From" address that outgoing alert emails will show.
# Starts blank. Shown as a plain text input.
seed_setting(
  key:        "email_from_address",
  value:      "",
  category:   "email",
  label:      "From address (usually same as username)",
  input_type: "text"
)

# Setting holding the address that alert emails get sent TO. Starts blank.
# Shown as a plain text input.
seed_setting(
  key:        "email_to_address",
  value:      "",
  category:   "email",
  label:      "Send alerts to this address",
  input_type: "text"
)

# -------------------------------------------------------------------------
# DISCORD ALERT SETTINGS
# -------------------------------------------------------------------------
# Setting controlling whether Discord alerts are enabled at all. Defaults
# to "false" (off), shown as a boolean input.
seed_setting(
  key:        "discord_enabled",
  value:      "false",
  category:   "discord",
  label:      "Enable Discord alerts",
  input_type: "boolean"
)

# Setting holding the Discord "webhook" URL to post alert messages to (a
# webhook is a special URL Discord generates per-channel that lets outside
# tools post messages into that channel without needing a full bot/login).
# Starts blank. Shown as a plain text input.
seed_setting(
  key:        "discord_webhook_url",
  value:      "",
  category:   "discord",
  label:      "Discord webhook URL (create one in your server's channel settings)",
  input_type: "text"
)

# -------------------------------------------------------------------------
# SMS SETTINGS (disabled, requires paid Twilio account)
# -------------------------------------------------------------------------
# Setting controlling whether SMS text-message alerts are enabled at all.
# Defaults to "false" (off), the label notes this requires a paid Twilio
# account (Twilio is a third-party service used to send text messages
# programmatically) to actually work. Shown as a boolean input.
seed_setting(
  key:        "sms_enabled",
  value:      "false",
  category:   "sms",
  label:      "Enable SMS alerts (requires paid Twilio account, see docs)",
  input_type: "boolean"
)

# Setting holding the Twilio "Account SID", Twilio's term for the unique
# identifier of a Twilio account (SID = "Subject Identifier"). Starts
# blank. Shown as a plain text input.
seed_setting(
  key:        "sms_twilio_account_sid",
  value:      "",
  category:   "sms",
  label:      "Twilio Account SID",
  input_type: "text"
)

# Setting holding the Twilio "Auth Token", a secret credential used to
# authenticate API requests to Twilio. Starts blank. `input_type:
# "password"` masks it in the UI, same caveat as email_smtp_password above:
# it is still stored as plain text in the database.
seed_setting(
  key:        "sms_twilio_auth_token",
  value:      "",
  category:   "sms",
  label:      "Twilio Auth Token",
  input_type: "password"
)

# Setting holding the phone number that SMS alerts are sent FROM (a number
# provisioned through Twilio). Starts blank. Shown as a plain text input.
seed_setting(
  key:        "sms_from_number",
  value:      "",
  category:   "sms",
  label:      "Twilio phone number to send from (e.g. +14805551234)",
  input_type: "text"
)

# Setting holding the phone number that SMS alerts are sent TO (the user's
# own phone). Starts blank. Shown as a plain text input.
seed_setting(
  key:        "sms_to_number",
  value:      "",
  category:   "sms",
  label:      "Your phone number to receive alerts (e.g. +14805559876)",
  input_type: "text"
)

# -------------------------------------------------------------------------
# HISTORY / DISPLAY SETTINGS
# -------------------------------------------------------------------------
# Setting controlling how many months of historical price data to retain
# before old records are purged. Shown as a number input.
seed_setting(
  key:        "history_keep_months",
  value:      "6",
  category:   "display",
  label:      "Months of price history to keep",
  input_type: "number"
)

# Setting controlling the default sort order applied to the results table.
# The value "monthly_price asc" is a raw SQL-style ORDER BY fragment
# (column name, then "asc" for ascending/lowest-first), shown as a
# "select" input, meaning the Settings page presumably renders this as a
# dropdown of preset sort options rather than free text.
seed_setting(
  key:        "display_default_sort",
  value:      "monthly_price asc",
  category:   "display",
  label:      "Default sort order for results table",
  input_type: "select"
)

# Setting controlling the price (in whole dollars) below which a unit's
# price badge is colored GREEN in the results table, see
# Unit#price_color_class in app/models/unit.rb, which reads this value
# instead of the $100/$150 breakpoints it used to hardcode. Shown as a
# number input.
seed_setting(
  key:        "display_price_green_max",
  value:      "99",
  category:   "display",
  label:      "Price badge is green at or below this amount ($)",
  input_type: "number"
)

# Setting controlling the price (in whole dollars) below which a unit's
# price badge is colored YELLOW rather than RED, a price strictly above
# both this and display_price_green_max above shows red. Shown as a number
# input.
seed_setting(
  key:        "display_price_yellow_max",
  value:      "149",
  category:   "display",
  label:      "Price badge is yellow at or below this amount ($), above it, red",
  input_type: "number"
)

# Prints a blank line to the console, purely for visual spacing in the
# terminal output.
puts ""
# Prints a summary line. `#{Setting.count}` is string interpolation (see
# the explanation above `seed_setting`'s closing `puts` line), it runs
# `Setting.count`, an ActiveRecord method that asks the database how many
# rows currently exist in the "settings" table, and inserts that number
# into the printed string.
puts "✓ Seeding complete. #{Setting.count} settings in database."
# Prints another blank line for spacing.
puts ""
# Prints the first line of a short "what to do next" guide for whoever just
# ran this seed script.
puts "Next steps:"
# Prints an instruction to start the app using the project's start script.
puts "  1. Start the app:  ./start.sh"
# Prints an instruction for which local URL to open in a browser.
puts "  2. Open browser:   http://storagefinder.local"
# Prints an instruction pointing to the Settings page for configuring the
# email/Discord alert settings seeded above.
puts "  3. Go to Settings to configure email/Discord alerts"
