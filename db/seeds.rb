# =============================================================================
# DATABASE SEEDS
# =============================================================================
# Seeds are default data inserted into the database when you run:
#   rails db:seed
#
# This file sets up the default settings that appear on the Settings page.
# It uses find_or_create_by so running seeds twice doesn't create duplicates.
# =============================================================================

puts "Seeding default settings..."

# Helper method to create a setting if it doesn't already exist
def seed_setting(key:, value: nil, category:, label:, input_type: "text")
  Setting.find_or_create_by(key: key) do |s|
    s.value      = value
    s.category   = category
    s.label      = label
    s.input_type = input_type
  end
  puts "  ✓ Setting: #{key}"
end

# -------------------------------------------------------------------------
# CRAWL SETTINGS
# -------------------------------------------------------------------------
seed_setting(
  key:        "crawl_default_radius_miles",
  value:      "100",
  category:   "crawl",
  label:      "Default search radius (miles)",
  input_type: "number"
)

seed_setting(
  key:        "crawl_max_retries",
  value:      "3",
  category:   "crawl",
  label:      "Max retries per page",
  input_type: "number"
)

seed_setting(
  key:        "crawl_delay_between_requests_ms",
  value:      "2000",
  category:   "crawl",
  label:      "Delay between requests (milliseconds) — increase on slow hardware",
  input_type: "number"
)

seed_setting(
  key:        "crawl_headless",
  value:      "true",
  category:   "crawl",
  label:      "Run browser in headless mode (invisible)",
  input_type: "boolean"
)

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
seed_setting(
  key:        "schedule_enabled",
  value:      "false",
  category:   "schedule",
  label:      "Enable scheduled automatic crawls",
  input_type: "boolean"
)

seed_setting(
  key:        "schedule_cron",
  value:      "0 6 * * *",
  category:   "schedule",
  label:      "Schedule (cron format) — default is every day at 6:00 AM",
  input_type: "text"
)

seed_setting(
  key:        "schedule_city",
  value:      "",
  category:   "schedule",
  label:      "City to search on schedule (leave blank to use last manual search)",
  input_type: "text"
)

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
seed_setting(
  key:        "email_enabled",
  value:      "false",
  category:   "email",
  label:      "Enable email alerts",
  input_type: "boolean"
)

seed_setting(
  key:        "email_smtp_host",
  value:      "smtp.gmail.com",
  category:   "email",
  label:      "SMTP server hostname",
  input_type: "text"
)

seed_setting(
  key:        "email_smtp_port",
  value:      "587",
  category:   "email",
  label:      "SMTP port (587 for Gmail TLS, 465 for SSL)",
  input_type: "number"
)

seed_setting(
  key:        "email_smtp_username",
  value:      "",
  category:   "email",
  label:      "SMTP username (your Gmail address)",
  input_type: "text"
)

seed_setting(
  key:        "email_smtp_password",
  value:      "",
  category:   "email",
  label:      "SMTP password or app password",
  input_type: "password"
)

seed_setting(
  key:        "email_from_address",
  value:      "",
  category:   "email",
  label:      "From address (usually same as username)",
  input_type: "text"
)

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
seed_setting(
  key:        "discord_enabled",
  value:      "false",
  category:   "discord",
  label:      "Enable Discord alerts",
  input_type: "boolean"
)

seed_setting(
  key:        "discord_webhook_url",
  value:      "",
  category:   "discord",
  label:      "Discord webhook URL (create one in your server's channel settings)",
  input_type: "text"
)

# -------------------------------------------------------------------------
# SMS SETTINGS (disabled — requires paid Twilio account)
# -------------------------------------------------------------------------
seed_setting(
  key:        "sms_enabled",
  value:      "false",
  category:   "sms",
  label:      "Enable SMS alerts (requires paid Twilio account — see docs)",
  input_type: "boolean"
)

seed_setting(
  key:        "sms_twilio_account_sid",
  value:      "",
  category:   "sms",
  label:      "Twilio Account SID",
  input_type: "text"
)

seed_setting(
  key:        "sms_twilio_auth_token",
  value:      "",
  category:   "sms",
  label:      "Twilio Auth Token",
  input_type: "password"
)

seed_setting(
  key:        "sms_from_number",
  value:      "",
  category:   "sms",
  label:      "Twilio phone number to send from (e.g. +14805551234)",
  input_type: "text"
)

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
seed_setting(
  key:        "history_keep_months",
  value:      "6",
  category:   "display",
  label:      "Months of price history to keep",
  input_type: "number"
)

seed_setting(
  key:        "display_default_sort",
  value:      "monthly_price asc",
  category:   "display",
  label:      "Default sort order for results table",
  input_type: "select"
)

puts ""
puts "✓ Seeding complete. #{Setting.count} settings in database."
puts ""
puts "Next steps:"
puts "  1. Start the app:  ./start.sh"
puts "  2. Open browser:   http://storagefinder.local"
puts "  3. Go to Settings to configure email/Discord alerts"
