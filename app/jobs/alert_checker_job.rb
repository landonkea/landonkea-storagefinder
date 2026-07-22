# =============================================================================
# ALERT CHECKER JOB
# =============================================================================
# Runs after every crawl to check if any alert rules have been triggered.
# Compares current prices to previous crawl prices and fires notifications.
# =============================================================================

class AlertCheckerJob < ApplicationJob
  queue_as :alerts

  def perform(crawl_run_id:)
    current_run  = CrawlRun.find(crawl_run_id)
    active_rules = AlertRule.active

    if active_rules.empty?
      Rails.logger.info("[AlertCheckerJob] No active alert rules — skipping")
      return
    end

    # Get the previous completed crawl run (the one before this one)
    previous_run = CrawlRun.completed
                           .where("id < ?", current_run.id)
                           .order(id: :desc)
                           .first

    Rails.logger.info(
      "[AlertCheckerJob] Checking #{active_rules.count} alert rules. " \
      "Previous crawl: #{previous_run ? "##{previous_run.id}" : "none (first crawl)"}"
    )

    # For each active alert rule, check each unit from the current crawl
    active_rules.each do |rule|
      begin
        check_rule(rule, current_run, previous_run)
      rescue => e
        Rails.logger.error(
          "[AlertCheckerJob] Error checking rule '#{rule.name}': #{e.class}: #{e.message}"
        )
      end
    end
  end

  private

  def check_rule(rule, current_run, previous_run)
    # Get all units from the current crawl that could match this rule
    current_units = current_run.units.includes(:facility)
    current_units = current_units.where(size: rule.unit_size_filter) if rule.unit_size_filter.present?

    # For price_drop alerts, batch-load every previous-run unit's price up
    # front, keyed by [facility_id, size] — one query total instead of one
    # query per current unit (previous_run.units.where(...).first for each).
    previous_prices = {}
    if rule.trigger_type == "price_drop" && previous_run
      previous_run.units.select(:id, :facility_id, :size, :monthly_price, :web_special_price).find_each do |prev_unit|
        key = [ prev_unit.facility_id, prev_unit.size ]
        previous_prices[key] ||= prev_unit.best_price  # first match wins, same as the old .first
      end
    end

    triggered_units = []

    current_units.each do |unit|
      previous_price = previous_prices[[ unit.facility_id, unit.size ]]

      if rule.matches_unit?(unit, previous_price: previous_price)
        triggered_units << { unit: unit, previous_price: previous_price }
      end
    end

    if triggered_units.any?
      Rails.logger.info(
        "[AlertCheckerJob] Rule '#{rule.name}' triggered for #{triggered_units.length} units — sending alerts"
      )
      send_alerts(rule, triggered_units)
      rule.record_triggered!
    end
  end

  def send_alerts(rule, triggered_units)
    # Build the alert message
    message = AlertMessageBuilder.build(rule, triggered_units)

    # Send via each enabled delivery method
    AlertDeliveryService.deliver(rule, message)
  end
end
