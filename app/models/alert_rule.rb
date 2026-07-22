# =============================================================================
# ALERT RULE MODEL
# =============================================================================
# An AlertRule defines when to send a notification and where to send it.
#
# Trigger types:
#   "price_drop"      — fires when any unit's price drops compared to last crawl
#   "price_threshold" — fires when any unit's price falls below threshold_price
# =============================================================================

class AlertRule < ApplicationRecord
  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  validates :name,         presence:  { message: "Alert name is required" }
  validates :trigger_type, inclusion: {
    in:      %w[price_drop price_threshold],
    message: "Trigger type must be 'price_drop' or 'price_threshold'"
  }

  # threshold_price is required when trigger_type is "price_threshold"
  validates :threshold_price, presence: {
    message: "Threshold price is required when using price threshold trigger"
  }, if: -> { trigger_type == "price_threshold" }

  validates :threshold_price, numericality: {
    greater_than: 0,
    message:      "Threshold price must be greater than $0"
  }, allow_nil: true

  # At least one delivery method must be enabled
  validate :at_least_one_delivery_method

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  scope :active,     -> { where(active: true) }
  scope :for_email,  -> { where(email_enabled: true) }
  scope :for_discord, -> { where(discord_enabled: true) }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------

  # Check if this alert rule matches a given unit at its price
  # Returns true if this alert should fire for the given unit
  def matches_unit?(unit, previous_price: nil)
    # First check if the unit matches any company/size filters on this rule
    return false if company_filter.present? && unit.facility.company != company_filter
    return false if unit_size_filter.present? && unit.size != unit_size_filter

    # Now check the trigger condition
    case trigger_type
    when "price_threshold"
      # Fire if the unit's price is at or below the threshold
      unit.best_price.present? && unit.best_price <= threshold_price

    when "price_drop"
      # Fire if the price dropped compared to last crawl
      # Requires a previous price to compare against
      return false if previous_price.nil? || unit.best_price.nil?
      unit.best_price < previous_price

    else
      false
    end
  end

  # Returns a human-readable description of this rule
  def description
    parts = []

    case trigger_type
    when "price_threshold"
      parts << "Price drops below $#{threshold_price}"
    when "price_drop"
      parts << "Any price drop"
    end

    parts << "for #{unit_size_filter}" if unit_size_filter.present?
    parts << "at #{company_filter}"    if company_filter.present?

    delivery = []
    delivery << "Email"   if email_enabled?
    delivery << "Discord" if discord_enabled?
    delivery << "SMS"     if sms_enabled?

    parts << "→ #{delivery.join(", ")}" if delivery.any?

    parts.join(" ")
  end

  # Record that this alert fired right now
  def record_triggered!
    update_column(:last_triggered_at, Time.current)
  end

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  # Validation: at least one of email, discord, or sms must be enabled
  def at_least_one_delivery_method
    unless email_enabled? || discord_enabled? || sms_enabled?
      errors.add(:base, "At least one delivery method (Email, Discord, or SMS) must be enabled")
    end
  end
end
