require "test_helper"

class AlertRulesControllerTest < ActionDispatch::IntegrationTest
  test "index lists alert rules" do
    get alert_rules_path
    assert_response :success
  end

  test "show renders a single rule" do
    get alert_rule_path(alert_rules(:price_drop_rule))
    assert_response :success
  end

  test "show redirects with an alert when the rule doesn't exist" do
    get alert_rule_path(id: 999_999)
    assert_redirected_to alert_rules_path
    assert_equal "Alert rule not found.", flash[:alert]
  end

  test "new renders the form" do
    get new_alert_rule_path
    assert_response :success
  end

  test "create saves a valid rule and redirects" do
    assert_difference "AlertRule.count", 1 do
      post alert_rules_path, params: {
        alert_rule: {
          name: "New rule", trigger_type: "price_threshold", threshold_price: "50",
          email_enabled: "true", email_address: "x@example.com"
        }
      }
    end

    assert_redirected_to alert_rules_path
  end

  test "create re-renders the form with errors for an invalid rule" do
    assert_no_difference "AlertRule.count" do
      post alert_rules_path, params: {
        alert_rule: { name: "", trigger_type: "price_threshold", threshold_price: "50" }
      }
    end

    assert_response :unprocessable_content
  end

  test "edit renders the form" do
    get edit_alert_rule_path(alert_rules(:price_drop_rule))
    assert_response :success
  end

  test "update saves changes and redirects" do
    rule = alert_rules(:price_drop_rule)

    patch alert_rule_path(rule), params: { alert_rule: { name: "Renamed rule" } }

    assert_redirected_to alert_rules_path
    assert_equal "Renamed rule", rule.reload.name
  end

  test "update re-renders the form with errors for invalid changes" do
    rule = alert_rules(:price_drop_rule)

    patch alert_rule_path(rule), params: {
      alert_rule: { email_enabled: "false", discord_enabled: "false", sms_enabled: "false" }
    }

    assert_response :unprocessable_content
  end

  test "destroy deletes the rule and redirects" do
    rule = alert_rules(:price_drop_rule)

    assert_difference "AlertRule.count", -1 do
      delete alert_rule_path(rule)
    end

    assert_redirected_to alert_rules_path
  end
end
