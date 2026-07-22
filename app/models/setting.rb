# =============================================================================
# SETTING MODEL
# =============================================================================
# Settings is a key-value store for app configuration.
# Instead of editing config files, users change settings through the UI.
#
# Example keys: "smtp_host", "discord_webhook_url", "crawl_default_radius_miles"
#
# Usage:
#   Setting.get("smtp_host")           # Returns the value string
#   Setting.set("smtp_host", "smtp.gmail.com")  # Updates the value
# =============================================================================

class Setting < ApplicationRecord
  # Settings hold secrets (SMTP password, Discord webhook URL, Twilio auth
  # token, ...) alongside plain config values, all in the same generic
  # key/value column. Encrypting the whole column is simpler and safer than
  # trying to track which keys are "sensitive" — non-secret values just get
  # encrypted too, at no real cost.
  encrypts :value

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  validates :key, presence:   { message: "Setting key is required" }
  validates :key, uniqueness: { message: "A setting with this key already exists" }

  # ---------------------------------------------------------------------------
  # CLASS METHODS — the main interface for reading/writing settings
  # ---------------------------------------------------------------------------

  # Get a setting value by key
  # Returns the value as a string, or default_value if the key doesn't exist
  #
  # Usage: Setting.get("smtp_host")
  #        Setting.get("crawl_parallel_companies", default: "2")
  def self.get(key, default: nil)
    record = find_by(key: key)

    if record.nil?
      # Log a warning — this might mean a seed wasn't run, or a key was mistyped
      Rails.logger.warn("[Setting] Key '#{key}' not found in settings table. Returning default: #{default.inspect}")
      return default
    end

    # Cast the value to the right type based on input_type
    cast_value(record.value, record.input_type)
  end

  # Set a setting value by key
  # Creates the record if it doesn't exist (upsert behavior)
  #
  # Usage: Setting.set("smtp_host", "smtp.gmail.com")
  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.to_s
    record.save!
    value
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[Setting] Failed to save setting '#{key}': #{e.message}")
    raise
  end

  # Get multiple settings at once, returned as a hash
  # Usage: Setting.get_all("email") returns all settings in the "email" category
  def self.get_all(category = nil)
    scope = category.present? ? where(category: category) : all
    scope.each_with_object({}) do |s, hash|
      hash[s.key] = cast_value(s.value, s.input_type)
    end
  end

  # Returns true/false for boolean settings
  # Usage: Setting.enabled?("email_enabled")
  def self.enabled?(key)
    get(key) == true
  end

  # ---------------------------------------------------------------------------
  # PRIVATE CLASS METHODS
  # ---------------------------------------------------------------------------
  private_class_method def self.cast_value(value, input_type)
    return nil if value.nil?

    case input_type
    when "boolean"
      # Convert "true"/"false" string to actual boolean
      value.to_s.downcase == "true"
    when "number"
      # Convert to integer or float depending on whether there's a decimal
      # Guard against nil — return 0 rather than crash
      value.to_s.include?(".") ? value.to_f : value.to_i
    else
      # Return as string for text, password, select, and anything else
      value.to_s
    end
  end
end
