require "test_helper"

class AlertCheckerJobTest < ActiveSupport::TestCase
  test "does nothing when there are no active alert rules" do
    AlertRule.update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    assert AlertRule.where.not(last_triggered_at: nil).none?
  end

  test "fires a price_drop alert when a unit's price dropped since the previous crawl" do
    # current_gilbert_10x10 ($120) is cheaper than previous_gilbert_10x10 ($150)
    # at the same facility+size — see test/fixtures/units.yml
    AlertRule.where.not(id: alert_rules(:price_drop_rule).id).update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    assert_not_nil alert_rules(:price_drop_rule).reload.last_triggered_at
  end

  test "does not fire a price_drop alert when the price didn't drop" do
    rule = alert_rules(:price_drop_rule)
    AlertRule.where.not(id: rule.id).update_all(active: false)

    # Make the current unit MORE expensive than the previous one, so no drop occurred
    units(:current_gilbert_10x10).update!(monthly_price: 999)
    units(:current_mesa_10x15).update!(monthly_price: 999)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    assert_nil rule.reload.last_triggered_at
  end

  test "fires a price_threshold alert when a unit is at or below the threshold" do
    # price_threshold_rule's threshold is $100; current_mesa_10x15 is $90
    rule = alert_rules(:price_threshold_rule)
    AlertRule.where.not(id: rule.id).update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    assert_not_nil rule.reload.last_triggered_at
  end

  test "does not fire when there is no previous crawl to compare against" do
    rule = alert_rules(:price_drop_rule)
    AlertRule.where.not(id: rule.id).update_all(active: false)
    CrawlRun.completed.destroy_all # remove fixture crawl runs so there's truly no "previous" one

    first_ever_run = CrawlRun.create!(
      search_city: "Brand New City", search_radius_miles: 25, status: "completed", completed_at: Time.current
    )
    Unit.create!(
      facility: facilities(:gilbert_public_storage), crawl_run: first_ever_run,
      size: "10x10", monthly_price: 50, collected_at: Time.current
    )

    AlertCheckerJob.perform_now(crawl_run_id: first_ever_run.id)

    assert_nil rule.reload.last_triggered_at
  end

  test "unit_size_filter narrows which units are checked" do
    rule = alert_rules(:price_threshold_rule)
    rule.update!(unit_size_filter: "10x10") # excludes the $90 10x15 unit that would otherwise trigger it
    AlertRule.where.not(id: rule.id).update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    assert_nil rule.reload.last_triggered_at
  end
end
