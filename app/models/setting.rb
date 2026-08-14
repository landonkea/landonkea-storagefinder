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

# `class Setting < ApplicationRecord` defines a Ruby class named Setting
# that inherits from ApplicationRecord (see app/models/application_record.rb).
# Inheriting from ApplicationRecord makes this an "ActiveRecord model": each
# instance represents one row of the "settings" database table, here, each
# row is one key/value configuration pair (e.g. key: "smtp_host", value:
# "smtp.gmail.com"), rather than one row per distinct real-world "thing"
# like a Facility or Unit would be.
class Setting < ApplicationRecord
  # Settings hold secrets (SMTP password, Discord webhook URL, Twilio auth
  # token, ...) alongside plain config values, all in the same generic
  # key/value column. Encrypting the whole column is simpler and safer than
  # trying to track which keys are "sensitive", non-secret values just get
  # encrypted too, at no real cost.
  #
  # `encrypts :value` is a built-in Rails method (Active Record Encryption)
  # that transparently encrypts the `value` column before it's written to
  # the database, and transparently decrypts it when read back through
  # normal Ruby code (e.g. `setting.value`), so the rest of this file (and
  # the rest of the app) can keep treating `value` like a plain string,
  # while the actual bytes stored in the database are ciphertext.
  encrypts :value

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # `validates` declares a rule a record must satisfy before Rails allows it
  # to be saved; if the rule fails, Rails blocks the save and records a
  # human-readable error message (via `record.errors`) instead.

  # Requires `key` to be present (not nil, not an empty string).
  validates :key, presence:   { message: "Setting key is required" }
  # Requires `key` to be unique across all Setting rows, prevents two
  # different rows from both claiming to be, say, "smtp_host", which would
  # make `Setting.get("smtp_host")` ambiguous.
  validates :key, uniqueness: { message: "A setting with this key already exists" }

  # ---------------------------------------------------------------------------
  # CLASS METHODS, the main interface for reading/writing settings
  # ---------------------------------------------------------------------------
  # `def self.method_name` defines a CLASS method, called directly on the
  # class itself, e.g. `Setting.get("smtp_host")`, rather than needing to
  # first look up/instantiate one particular Setting record by hand. This
  # is what lets the rest of the app treat Setting like a simple key/value
  # API (`Setting.get(...)` / `Setting.set(...)`) without dealing with
  # ActiveRecord query methods directly.

  # Get a setting value by key
  # Returns the value as a string, or default_value if the key doesn't exist
  #
  # Usage: Setting.get("smtp_host")
  #        Setting.get("crawl_parallel_companies", default: "2")
  #
  # `default: nil` is an optional keyword argument, callers can supply a
  # fallback value to use when the key isn't found, or omit it (defaulting
  # to nil).
  def self.get(key, default: nil)
    # `find_by(key: key)` looks up a single Setting row whose `key` column
    # matches the given value, returning nil (rather than raising an error)
    # if no row matches, unlike `find`, which raises when nothing's found.
    record = find_by(key: key)

    if record.nil?
      # Log a warning, this might mean a seed wasn't run, or a key was mistyped
      # `default.inspect` converts `default` to its Ruby-literal debug
      # representation (e.g. nil becomes the text "nil", a string gets
      # quotes around it), `.inspect` is generally preferred over `.to_s`
      # in log/debug messages because it distinguishes things like nil from
      # an empty string, which `.to_s` would make look identical ("").
      Rails.logger.warn("[Setting] Key '#{key}' not found in settings table. Returning default: #{default.inspect}")
      # Returns the caller-supplied default (or nil) and exits the method
      # immediately, `return` here is used explicitly (rather than relying
      # on it being the last expression) because there's more code below
      # that should NOT run in this branch.
      return default
    end
    # `end` closes the `if record.nil?` block above.

    # Cast the value to the right type based on input_type
    # Calls the private class method cast_value (defined at the bottom of
    # this file) to convert the raw stored string into the appropriate Ruby
    # type (boolean, number, or string) based on this setting's
    # `input_type` column. This is the method's return value.
    cast_value(record.value, record.input_type)
  end
  # `end` closes the `def self.get` class method definition.

  # Set a setting value by key
  # Creates the record if it doesn't exist (upsert behavior)
  #
  # Usage: Setting.set("smtp_host", "smtp.gmail.com")
  def self.set(key, value)
    # `find_or_initialize_by(key: key)` looks for an existing Setting row
    # with this key; if found, returns it (not yet saved to any changes);
    # if NOT found, builds a brand-new, unsaved Setting object with `key`
    # pre-filled, either way, `record` ends up as an object ready to have
    # its `value` set and then be saved. This is what gives `set` its
    # "upsert" (update-or-insert) behavior in one method.
    record = find_or_initialize_by(key: key)
    # `value.to_s` converts whatever was passed in (could be a number,
    # boolean, etc.) into a plain string before storing it, since the
    # underlying database column is text-based and type information is
    # instead tracked separately via `input_type`.
    record.value = value.to_s
    # `save!` writes the record to the database, running validations
    # first; the `!` variant raises `ActiveRecord::RecordInvalid` if
    # validation fails, instead of silently returning false.
    record.save!
    # Returns the (original, un-stringified) `value` argument back to the
    # caller, this is the method's return value, useful for chaining like
    # `result = Setting.set("x", 5)`.
    value
  # `rescue ActiveRecord::RecordInvalid => e` catches specifically the
  # exception type raised by `save!` above when validation fails, storing
  # it in the local variable `e`. Placing `rescue` directly under `def`
  # (without a `begin`) is Ruby's shorthand for wrapping the ENTIRE method
  # body in an implicit begin/rescue.
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[Setting] Failed to save setting '#{key}': #{e.message}")
    # `raise` with no argument re-raises the SAME exception that was just
    # caught, so the error is logged here for visibility, but still
    # propagates up to whatever code called `Setting.set`, rather than
    # being silently swallowed.
    raise
  end
  # `end` closes the `def self.set` class method definition (including its
  # attached `rescue` clause).

  # Get multiple settings at once, returned as a hash
  # Usage: Setting.get_all("email") returns all settings in the "email" category
  #
  # `category = nil` is an optional POSITIONAL argument (not a keyword
  # argument like `default:` above) with a default of nil, callers can
  # write `Setting.get_all` (category omitted) or `Setting.get_all("email")`.
  def self.get_all(category = nil)
    # Ternary conditional: `condition ? value_if_true : value_if_false`.
    # If a category was given (and isn't blank), scope the query to only
    # Setting rows with that category; otherwise `all` (a Rails method
    # returning every row) is used as the starting query.
    scope = category.present? ? where(category: category) : all
    # `.each_with_object({})` iterates over `scope` (each Setting record,
    # named `s` inside the block) while building up a result, the `{}`
    # passed in is a brand-new empty Ruby Hash (key-value map) that gets
    # threaded through and returned by the whole call. `do |s, hash| ...
    # end` is the block: `s` is the current Setting record, `hash` is that
    # same accumulating Hash object on every iteration.
    scope.each_with_object({}) do |s, hash|
      # `hash[s.key] = ...` sets the entry in the hash keyed by this
      # setting's `key` column, with its value converted to the right Ruby
      # type via cast_value. Because `hash` is the SAME object being
      # returned by each_with_object, these assignments accumulate across
      # every record in `scope`.
      hash[s.key] = cast_value(s.value, s.input_type)
    end
    # `end` closes the `do |s, hash| ... end` block above; `each_with_
    # object` returns the fully-populated hash, which is this method's
    # return value.
  end
  # `end` closes the `def self.get_all` class method definition.

  # Returns true/false for boolean settings
  # Usage: Setting.enabled?("email_enabled")
  def self.enabled?(key)
    # Calls `get` (defined above) to fetch and type-cast the value, then
    # compares it against the literal boolean `true`, so this only
    # returns true when the setting is BOTH found AND cast to exactly
    # `true` (not just any "truthy" Ruby value).
    get(key) == true
  end
  # `end` closes the `def self.enabled?` class method definition.

  # ---------------------------------------------------------------------------
  # PRIVATE CLASS METHODS
  # ---------------------------------------------------------------------------
  # `private_class_method def self.cast_value(...)` marks the class method
  # defined right after it as private, callable only from inside this
  # class's own code (like `get` and `get_all` above), not from outside
  # code such as `Setting.cast_value(...)` in a controller. This differs
  # from the plain `private` keyword used in other model files in this app
  # (e.g. AlertRule), which only affects INSTANCE methods, not class
  # methods, class methods need this separate `private_class_method` form.
  private_class_method def self.cast_value(value, input_type)
    # If there's no stored value at all, there's nothing to cast, return
    # nil immediately regardless of input_type.
    return nil if value.nil?

    case input_type
    when "boolean"
      # Convert "true"/"false" string to actual boolean
      # `value.to_s.downcase == "true"` normalizes the stored string to
      # lowercase (so "True", "TRUE", "true" all match) and compares it,
      # anything other than the literal text "true" (case-insensitively)
      # becomes Ruby's `false`.
      value.to_s.downcase == "true"
    when "number"
      # Convert to integer or float depending on whether there's a decimal
      # Guard against nil, return 0 rather than crash
      # `value.to_s.include?(".")` checks whether the stored string
      # contains a decimal point. Ternary: if it does, `.to_f` converts to
      # a floating-point number; otherwise `.to_i` converts to a whole
      # integer. Both `.to_f`/`.to_i` return 0/0.0 for unparseable text
      # rather than raising an error, which is the "guard against crash"
      # behavior the comment refers to.
      value.to_s.include?(".") ? value.to_f : value.to_i
    else
      # Return as string for text, password, select, and anything else
      value.to_s
    end
    # `end` closes the `case input_type` block above; its result is this
    # method's return value.
  end
  # `end` closes the `def self.cast_value` method definition.
end
# `end` closes the `class Setting < ApplicationRecord` block that started at
# the top of the file.
