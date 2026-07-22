require "test_helper"

class AlertMessageBuilderTest < ActiveSupport::TestCase
  def triggered_units
    [
      { unit: units(:current_gilbert_10x10), previous_price: 150 },
      { unit: units(:current_mesa_10x15), previous_price: nil }
    ]
  end

  test "build returns subject, text_body, html_body, and sms_body" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    assert message[:subject].present?
    assert message[:text_body].present?
    assert message[:html_body].present?
    assert message[:sms_body].present?
  end

  test "price_drop subject mentions the number of units" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)
    assert_match(/2 units dropped in price/, message[:subject])
  end

  test "price_threshold subject mentions the threshold" do
    message = AlertMessageBuilder.build(alert_rules(:price_threshold_rule), triggered_units)
    assert_match(/below \$100\.0/, message[:subject])
  end

  test "text_body lists each unit's facility, size, and price" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    assert_match "Public Storage", message[:text_body]
    assert_match "10x10", message[:text_body]
    assert_match(/Previous price: \$150/, message[:text_body])
  end

  test "text_body truncates to 10 units and notes how many more there are" do
    many_units = (1..12).map { { unit: units(:current_gilbert_10x10), previous_price: nil } }
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), many_units)

    assert_match(/and 2 more units/, message[:text_body])
  end

  test "html_body renders a table row per unit" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    assert_equal 2, message[:html_body].scan("<tr>").length - 1 # -1 for the header row
  end

  test "sms_body is a single short line about the first unit" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    assert_match "Public Storage", message[:sms_body]
    refute_includes message[:sms_body], "\n"
  end
end
