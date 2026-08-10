# =============================================================================
# ALERT RULE MODEL
# =============================================================================
# An AlertRule defines when to send a notification and where to send it.
#
# Trigger types:
#   "price_drop"     , fires when any unit's price drops compared to last crawl
#   "price_threshold", fires when any unit's price falls below threshold_price
# =============================================================================

# `class AlertRule < ApplicationRecord` defines a Ruby class named AlertRule
# that inherits from ApplicationRecord (see app/models/application_record.rb).
# Inheriting from ApplicationRecord (which itself inherits from
# `ActiveRecord::Base`) is what makes this an "ActiveRecord model", Ruby
# code that represents one row of a database table (here, the
# "alert_rules" table, inferred automatically from the class name). Each
# instance of AlertRule corresponds to one row; each column in the table
# (name, trigger_type, threshold_price, etc.) is automatically readable and
# writable as if it were a plain Ruby attribute/method, e.g. `rule.name`.
class AlertRule < ApplicationRecord
  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # `validates` is a Rails class method that declares a rule a record must
  # satisfy before it's allowed to be saved to the database. If a validation
  # fails, Rails refuses to save and instead adds a human-readable error
  # message you can display back to the user (accessed via `record.errors`).

  # Requires the `name` attribute to be present (not nil and not an empty
  # string). `presence:` takes a hash of options; `message:` customizes the
  # text shown when this validation fails instead of Rails' generic default.
  validates :name,         presence:  { message: "Alert name is required" }
  # Requires `trigger_type` to be one of the values listed in the `in:`
  # array. `%w[price_drop price_threshold]` is Ruby's "percent-w" array
  # literal shorthand, it's exactly equivalent to
  # `["price_drop", "price_threshold"]` but saves you from typing quotes
  # and commas around each word.
  validates :trigger_type, inclusion: {
    in:      %w[price_drop price_threshold],
    message: "Trigger type must be 'price_drop' or 'price_threshold'"
  }

  # threshold_price is required when trigger_type is "price_threshold"
  # This validation is CONDITIONAL: the `if:` option takes a lambda (an
  # inline anonymous function, `-> { ... }`) that Rails calls on the record
  # being validated. Only when that lambda returns true does Rails actually
  # check the `presence:` rule below it, so threshold_price is only
  # required when this particular rule's trigger_type is "price_threshold".
  validates :threshold_price, presence: {
    message: "Threshold price is required when using price threshold trigger"
  }, if: -> { trigger_type == "price_threshold" }

  # Requires threshold_price (when present) to be a number greater than
  # zero. `allow_nil: true` means this specific validation is skipped
  # entirely when threshold_price is nil, nil is already handled (or not)
  # by the conditional presence validation just above.
  validates :threshold_price, numericality: {
    greater_than: 0,
    message:      "Threshold price must be greater than $0"
  }, allow_nil: true

  # cooldown_minutes must be zero or a positive whole number of minutes.
  # `0` (the column's default, see the migration
  # db/migrate/20260803000000_add_cooldown_minutes_to_alert_rules.rb) means
  # "no cooldown, fire every time the trigger condition matches", today's
  # original behavior. `greater_than_or_equal_to: 0` allows exactly 0 as
  # well as any positive number; `only_integer: true` rejects fractional
  # minutes like 1.5.
  validates :cooldown_minutes, numericality: {
    greater_than_or_equal_to: 0,
    only_integer:              true,
    message:                   "Cooldown must be a whole number of minutes (0 or more)"
  }

  # At least one delivery method must be enabled
  # `validate` (no trailing "s", unlike `validates` above) registers a
  # CUSTOM validation method by name (as a symbol) rather than a built-in
  # rule like `presence` or `numericality`. Rails will call the
  # `at_least_one_delivery_method` private method (defined near the bottom
  # of this file) every time a record is validated.
  validate :at_least_one_delivery_method

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  # A "scope" is a named, reusable database query you can call like a class
  # method, e.g. `AlertRule.active`. Each one here is defined with a lambda
  # (`-> { ... }`) containing a `where(...)` query; Rails turns that into a
  # chainable, class-level method of the same name.

  # Returns only alert rules whose `active` column is true.
  scope :active,     -> { where(active: true) }
  # Returns only alert rules that have email delivery turned on.
  scope :for_email,  -> { where(email_enabled: true) }
  # Returns only alert rules that have Discord delivery turned on.
  scope :for_discord, -> { where(discord_enabled: true) }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------
  # Everything below (until `private`) is a regular Ruby instance method,
  # callable on one particular AlertRule record, e.g. `some_rule.matches_unit?(...)`.

  # Check if this alert rule matches a given unit at its price
  # Returns true if this alert should fire for the given unit
  #
  # `def matches_unit?(unit, previous_price: nil)` defines a method named
  # `matches_unit?` (the trailing `?` is just a Ruby naming convention
  # meaning "this method returns true/false", it has no special behavior).
  # `unit` is a required positional argument. `previous_price: nil` is a
  # "keyword argument" with a default value, callers can either omit it
  # (it defaults to nil) or pass it explicitly like
  # `matches_unit?(some_unit, previous_price: 79.00)`.
  def matches_unit?(unit, previous_price: nil)
    # First check if the unit matches any company/size filters on this rule
    # `return false if ...` is Ruby's inline conditional "modifier" form,
    # equivalent to `if ...; return false; end` but on one line. It exits
    # the method immediately, returning false, when the condition is true.
    # `.present?` is a Rails helper meaning "not nil and not blank/empty."
    # `unit.facility` follows the belongs_to/has_many association from Unit
    # to Facility (see app/models/unit.rb and app/models/facility.rb) to
    # fetch the related Facility record, then reads its `company` column.
    return false if company_filter.present? && unit.facility.company != company_filter
    return false if unit_size_filter.present? && unit.size != unit_size_filter

    # Now check the trigger condition
    # `case ... when ... when ... else ... end` is Ruby's multi-branch
    # conditional, similar to a switch statement in other languages. It
    # compares `trigger_type` against each `when` value in order and runs
    # the first branch that matches.
    case trigger_type
    when "price_threshold"
      # Fire if the unit's price is at or below the threshold
      # `unit.best_price` calls the best_price method defined on Unit (see
      # app/models/unit.rb), the price actually being compared/displayed.
      # `&&` is Ruby's "and": both sides must be true for the whole
      # expression to be true. This is also the return value of this
      # `when` branch (and thus of the whole `case` expression, and thus of
      # the method), since it's the last thing evaluated on this branch,
      # Ruby methods return whatever their last expression evaluates to.
      unit.best_price.present? && unit.best_price <= threshold_price

    when "price_drop"
      # Fire if the price dropped compared to last crawl
      # Requires a previous price to compare against
      # Bails out early (returning false) if we don't have enough data to
      # compare, either no previous price was supplied, or this unit has
      # no current best_price at all.
      return false if previous_price.nil? || unit.best_price.nil?
      # If we got past the guard above, compare: true only if the current
      # price is strictly less than the previous price (i.e. it dropped).
      unit.best_price < previous_price

    else
      # Any trigger_type other than the two handled above (shouldn't
      # normally happen thanks to the inclusion validation, but this is a
      # safe fallback), never fires.
      false
    end
    # `end` closes the `case trigger_type` block that started above.
  end
  # `end` closes the `def matches_unit?` method definition.

  # Returns a human-readable description of this rule
  def description
    # `parts = []` creates a new, empty Ruby array and stores it in the
    # local variable `parts`. We'll build up pieces of the description
    # string in this array, then join them together at the end.
    parts = []

    case trigger_type
    when "price_threshold"
      # `parts << "..."` uses the `<<` "shovel" operator to append a new
      # element onto the end of the `parts` array (mutates it in place).
      # `"...#{threshold_price}"` is Ruby string interpolation: whatever is
      # inside `#{ }` is evaluated as Ruby code and its result is inserted
      # into the string at that position.
      parts << "Price drops below $#{threshold_price}"
    when "price_drop"
      parts << "Any price drop"
    end
    # `end` closes the `case trigger_type` block above.

    # Appends a size-filter note only if a size filter is actually set.
    # `if unit_size_filter.present?` is the inline modifier form again,
    # the `parts <<` line only runs when the condition after `if` is true.
    parts << "for #{unit_size_filter}" if unit_size_filter.present?
    # Same idea, appending a company-filter note only if one is set.
    parts << "at #{company_filter}"    if company_filter.present?
    # Same idea again, noting the cooldown window only when one is actually
    # configured (cooldown_minutes > 0), most rules have no cooldown, so
    # this stays silent for them.
    parts << "(at most once per #{cooldown_minutes}min)" if cooldown_minutes.to_i > 0

    # `delivery = []` starts a fresh empty array for the list of delivery
    # channels this rule uses (Email/Discord/SMS).
    delivery = []
    # `email_enabled?` is an automatically-generated Rails "boolean query
    # method", for any database column whose name ends in `?`-suitable
    # boolean semantics (here, an `email_enabled` boolean column), Rails
    # generates a `email_enabled?` method that returns true/false.
    delivery << "Email"   if email_enabled?
    delivery << "Discord" if discord_enabled?
    delivery << "SMS"     if sms_enabled?

    # Only add the "→ ..." delivery summary if at least one channel was
    # added. `.any?` on an array returns true if it has at least one
    # element. `.join(", ")` turns the delivery array into a single string
    # with ", " between each item, e.g. "Email, Discord".
    parts << "→ #{delivery.join(", ")}" if delivery.any?

    # The method's return value: join every collected piece of `parts`
    # into one final sentence, separated by single spaces. This is the
    # last expression evaluated in the method, so it's what gets returned.
    parts.join(" ")
  end
  # `end` closes the `def description` method definition.

  # Is this rule currently in its "quiet hours" cooldown window?
  # Returns true if this rule fired recently enough that it should NOT fire
  # again yet, even if its trigger condition still matches on the current
  # crawl. Called by AlertCheckerJob#check_rule before sending a new alert.
  #
  # `cooldown_minutes.to_i <= 0` treats a nil/zero/negative cooldown as "no
  # cooldown configured", this rule can always fire again immediately.
  # `last_triggered_at.nil?` handles a rule that has never fired before
  # (nothing to cool down from yet).
  def in_cooldown?
    return false if cooldown_minutes.to_i <= 0
    return false if last_triggered_at.nil?

    # True while we're still within `cooldown_minutes` minutes of the last
    # time this rule fired. `cooldown_minutes.minutes` converts the plain
    # integer into a Rails duration; adding it to `last_triggered_at` gives
    # the exact moment the cooldown window ends; `> Time.current` is true
    # only while that moment is still in the future.
    (last_triggered_at + cooldown_minutes.minutes) > Time.current
  end
  # `end` closes the `def in_cooldown?` method definition.

  # Record that this alert fired right now
  def record_triggered!
    # The trailing `!` in the method name is a Ruby convention signaling
    # "this is the more dangerous/side-effecting variant" (here: it writes
    # to the database), it has no special language meaning, just a hint
    # to readers. `update_column` is a Rails method that updates a single
    # database column directly, WITHOUT running validations or callbacks
    # (unlike the normal `update`/`save` methods), useful for bookkeeping
    # fields like this timestamp where you don't want validation rules to
    # possibly block the write. `Time.current` returns the current time,
    # respecting the application's configured time zone (preferred over
    # plain `Time.now` in Rails apps for that reason).
    update_column(:last_triggered_at, Time.current)
  end
  # `end` closes the `def record_triggered!` method definition.

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  # The `private` keyword below marks everything after it (until the class
  # ends) as private, meaning these methods can only be called from inside
  # this class itself (e.g. by Rails' validation machinery), not from
  # outside code like controllers or views. It's a way of hiding
  # implementation details that aren't meant to be part of this model's
  # public interface.
  private

  # Validation: at least one of email, discord, or sms must be enabled
  # This is the custom validation method referenced earlier by
  # `validate :at_least_one_delivery_method`. Rails calls it automatically
  # whenever a record is validated (e.g. on save).
  def at_least_one_delivery_method
    # `unless` runs its block only when the condition is FALSE (it's the
    # opposite of `if`). Here: if none of the three delivery flags are
    # enabled, add a validation error.
    unless email_enabled? || discord_enabled? || sms_enabled?
      # `errors.add(:base, "...")` records a validation failure on this
      # record. `:base` is a special symbol meaning "this error isn't tied
      # to one specific field" (as opposed to `errors.add(:name, "...")`,
      # which would attach the error to the `name` field specifically),
      # appropriate here since the rule spans three different fields.
      errors.add(:base, "At least one delivery method (Email, Discord, or SMS) must be enabled")
    end
    # `end` closes the `unless` block above.
  end
  # `end` closes the `def at_least_one_delivery_method` method definition.
end
# `end` closes the `class AlertRule < ApplicationRecord` block that started
# at the top of the file.
