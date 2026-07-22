require "test_helper"

class AlertRuleTest < ActiveSupport::TestCase
  def valid_attributes
    { name: "Test rule", trigger_type: "price_threshold", threshold_price: 100, email_enabled: true, email_address: "x@example.com" }
  end

  test "requires a name" do
    rule = AlertRule.new(valid_attributes.merge(name: ""))
    refute rule.valid?
    assert_includes rule.errors[:name], "Alert name is required"
  end

  test "trigger_type must be price_drop or price_threshold" do
    rule = AlertRule.new(valid_attributes.merge(trigger_type: "bogus"))
    refute rule.valid?
    assert_includes rule.errors[:trigger_type], "Trigger type must be 'price_drop' or 'price_threshold'"
  end

  test "threshold_price is required for price_threshold rules" do
    rule = AlertRule.new(valid_attributes.merge(trigger_type: "price_threshold", threshold_price: nil))
    refute rule.valid?
    assert_includes rule.errors[:threshold_price], "Threshold price is required when using price threshold trigger"
  end

  test "threshold_price is not required for price_drop rules" do
    rule = AlertRule.new(valid_attributes.merge(trigger_type: "price_drop", threshold_price: nil))
    assert rule.valid?, rule.errors.full_messages.join(", ")
  end

  test "threshold_price must be greater than 0 when present" do
    rule = AlertRule.new(valid_attributes.merge(threshold_price: -5))
    refute rule.valid?
    assert_includes rule.errors[:threshold_price], "Threshold price must be greater than $0"
  end

  test "requires at least one delivery method enabled" do
    rule = AlertRule.new(valid_attributes.merge(email_enabled: false, discord_enabled: false, sms_enabled: false))
    refute rule.valid?
    assert_includes rule.errors[:base], "At least one delivery method (Email, Discord, or SMS) must be enabled"
  end

  test "active scope only returns active rules" do
    assert_includes AlertRule.active, alert_rules(:price_drop_rule)
    refute_includes AlertRule.active, alert_rules(:inactive_rule)
  end

  test "matches_unit? for price_threshold fires at or below the threshold" do
    rule = alert_rules(:price_threshold_rule) # threshold $100

    cheap_unit = Unit.new(monthly_price: 90, facility: facilities(:mesa_extra_space))
    at_threshold_unit = Unit.new(monthly_price: 100, facility: facilities(:mesa_extra_space))
    expensive_unit = Unit.new(monthly_price: 150, facility: facilities(:mesa_extra_space))

    assert rule.matches_unit?(cheap_unit)
    assert rule.matches_unit?(at_threshold_unit)
    refute rule.matches_unit?(expensive_unit)
  end

  test "matches_unit? for price_drop fires only when the price actually dropped" do
    rule = alert_rules(:price_drop_rule)
    unit = Unit.new(monthly_price: 90, facility: facilities(:mesa_extra_space))

    assert rule.matches_unit?(unit, previous_price: 100)
    refute rule.matches_unit?(unit, previous_price: 80)
    refute rule.matches_unit?(unit, previous_price: nil)
  end

  test "matches_unit? respects company_filter and unit_size_filter" do
    rule = alert_rules(:price_threshold_rule)
    rule.company_filter = "Extra Space Storage"

    matching_unit = Unit.new(monthly_price: 90, facility: facilities(:mesa_extra_space))
    other_company_unit = Unit.new(monthly_price: 90, facility: facilities(:gilbert_public_storage))

    assert rule.matches_unit?(matching_unit)
    refute rule.matches_unit?(other_company_unit)
  end

  test "description summarizes the rule" do
    rule = alert_rules(:price_threshold_rule)
    assert_match(/Price drops below \$100/, rule.description)
    assert_match(/Discord/, rule.description)
  end

  test "record_triggered! stamps last_triggered_at" do
    rule = alert_rules(:price_drop_rule)
    assert_nil rule.last_triggered_at

    rule.record_triggered!
    assert_not_nil rule.reload.last_triggered_at
  end
end
