# `require "test_helper"` loads test/test_helper.rb (Ruby's load path is
# configured so "test_helper" alone resolves to that file). That file boots
# Rails in test mode, stubs Geocoder so no test ever hits the real network
# for geocoding, and defines the `stub_any_instance` helper used elsewhere
# in this app's tests. Every test file in this app requires it first.
require "test_helper"

# `class AlertCheckerJobTest < ActiveSupport::TestCase` defines this file's
# test class, inheriting from ActiveSupport::TestCase (see test_helper.rb —
# that's the class `fixtures :all` and `stub_any_instance` were added to).
# Inheriting from it is what gives this class access to fixtures (like
# `crawl_runs(:current_completed)` below), assertion methods (`assert`,
# `assert_nil`, ...), and the `test "..." do ... end` syntax used for each
# test case.
#
# This file tests AlertCheckerJob (app/jobs/alert_checker_job.rb) — the
# background job that runs after every crawl to compare current unit prices
# against the previous crawl's prices and fire notifications for any
# AlertRule whose trigger condition matches.
class AlertCheckerJobTest < ActiveSupport::TestCase
  # `test "..." do ... end` is Rails' convenience syntax for defining one
  # Minitest test case — under the hood it turns the string into a method
  # name (spaces replaced, prefixed with "test_") and defines a real Ruby
  # method with that name containing the block's code. This test checks
  # that when there are no ACTIVE alert rules, the job does nothing at all.
  test "does nothing when there are no active alert rules" do
    # `AlertRule.update_all(active: false)` is an ActiveRecord class method
    # that updates every row in the alert_rules table directly with one SQL
    # UPDATE statement (bypassing validations/callbacks, unlike calling
    # `.save` on each record). This deactivates every alert rule fixture,
    # regardless of what test/fixtures/alert_rules.yml originally set.
    AlertRule.update_all(active: false)

    # `AlertCheckerJob.perform_now(...)` runs the job SYNCHRONOUSLY, right
    # here in the test, and waits for it to finish before moving to the
    # next line — as opposed to `perform_later`, which would just enqueue
    # it to run at some future point via ActiveJob's queue adapter. Tests
    # almost always want `perform_now` so assertions can run immediately
    # afterward, once the job's side effects have actually happened.
    # `crawl_run_id:` is a required keyword argument matching
    # AlertCheckerJob#perform's signature (see app/jobs/alert_checker_job.rb).
    # `crawl_runs(:current_completed)` looks up the CrawlRun fixture named
    # "current_completed" in test/fixtures/crawl_runs.yml, and `.id` reads
    # its database ID.
    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    # `AlertRule.where.not(last_triggered_at: nil)` builds a query for every
    # alert rule whose `last_triggered_at` column IS set (i.e. one that has
    # fired at some point). `.none?` returns true only if that query matches
    # ZERO rows. Combined, this asserts that no alert rule's
    # last_triggered_at got touched by the job run above — proving the job
    # really did nothing when every rule was inactive.
    assert AlertRule.where.not(last_triggered_at: nil).none?
  end
  # `end` closes the "does nothing when there are no active alert rules" test block above.

  test "fires a price_drop alert when a unit's price dropped since the previous crawl" do
    # current_gilbert_10x10 ($120) is cheaper than previous_gilbert_10x10 ($150)
    # at the same facility+size — see test/fixtures/units.yml
    # `AlertRule.where.not(id: alert_rules(:price_drop_rule).id)` selects
    # every alert rule EXCEPT the one named "price_drop_rule" in the
    # fixtures, and `.update_all(active: false)` deactivates all of those —
    # isolating this test so ONLY the price_drop_rule is active, meaning any
    # alert that fires must have come from that rule specifically.
    AlertRule.where.not(id: alert_rules(:price_drop_rule).id).update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    # `alert_rules(:price_drop_rule).reload` re-fetches this rule fresh from
    # the database — necessary because the job above updated the row
    # directly in the database, and the in-memory fixture object wouldn't
    # otherwise reflect that change without being reloaded.
    # `.last_triggered_at` reads the timestamp column that
    # AlertRule#record_triggered! sets when a rule fires (see
    # app/models/alert_rule.rb). `assert_not_nil` passes only if this is
    # NOT nil — proving the rule did fire.
    assert_not_nil alert_rules(:price_drop_rule).reload.last_triggered_at
  end
  # `end` closes the price_drop-alert-fires test block above.

  test "does not fire a price_drop alert when the price didn't drop" do
    # `rule = alert_rules(:price_drop_rule)` saves this fixture into a local
    # variable so it doesn't have to be looked up by name repeatedly below.
    rule = alert_rules(:price_drop_rule)
    AlertRule.where.not(id: rule.id).update_all(active: false)

    # Make the current unit MORE expensive than the previous one, so no drop occurred
    # `units(:current_gilbert_10x10).update!(monthly_price: 999)` looks up
    # the Unit fixture and immediately writes a new `monthly_price` to the
    # database via `.update!` (the trailing `!` means: raise an exception if
    # the update fails validation, rather than silently returning false).
    # Setting both current units' prices to $999 — much higher than their
    # fixture "previous" counterparts — guarantees neither unit's price
    # actually dropped, so the price_drop rule should NOT fire.
    units(:current_gilbert_10x10).update!(monthly_price: 999)
    units(:current_mesa_10x15).update!(monthly_price: 999)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    # `assert_nil` passes only if `rule.reload.last_triggered_at` really is
    # nil — i.e. the rule never fired, confirming the job correctly detected
    # there was no price drop.
    assert_nil rule.reload.last_triggered_at
  end
  # `end` closes the "does not fire...price didn't drop" test block above.

  test "fires a price_threshold alert when a unit is at or below the threshold" do
    # price_threshold_rule's threshold is $100; current_mesa_10x15 is $90
    rule = alert_rules(:price_threshold_rule)
    AlertRule.where.not(id: rule.id).update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    assert_not_nil rule.reload.last_triggered_at
  end
  # `end` closes the price_threshold-alert-fires test block above.

  test "does not fire when there is no previous crawl to compare against" do
    rule = alert_rules(:price_drop_rule)
    AlertRule.where.not(id: rule.id).update_all(active: false)
    # `CrawlRun.completed` is presumably a named scope (a saved, reusable
    # query — see app/models/crawl_run.rb) returning crawl runs whose status
    # is "completed". `.destroy_all` deletes every one of those rows (and,
    # per Rails' `dependent: :destroy` associations, their related Units
    # too), wiping out every fixture crawl run so this test can prove the
    # job's behavior when there is truly no PREVIOUS run to compare prices
    # against.
    CrawlRun.completed.destroy_all # remove fixture crawl runs so there's truly no "previous" one

    # `CrawlRun.create!(...)` builds a brand new CrawlRun row directly in
    # the database (the trailing `!` raises if it fails validation, rather
    # than returning false silently). This is the ONLY completed crawl run
    # that will exist once this line runs, so from AlertCheckerJob's
    # perspective it's "the first crawl ever" — there's nothing earlier to
    # compare against.
    first_ever_run = CrawlRun.create!(
      search_city: "Brand New City", search_radius_miles: 25, status: "completed", completed_at: Time.current
    )
    # Creates one Unit record tied to that brand-new crawl run, so the job
    # actually has something to check a price_drop rule against (even
    # though — per the test name — there's no PREVIOUS crawl to compare it
    # to, so the rule still shouldn't fire).
    Unit.create!(
      facility: facilities(:gilbert_public_storage), crawl_run: first_ever_run,
      size: "10x10", monthly_price: 50, collected_at: Time.current
    )

    AlertCheckerJob.perform_now(crawl_run_id: first_ever_run.id)

    assert_nil rule.reload.last_triggered_at
  end
  # `end` closes the "does not fire...no previous crawl" test block above.

  test "unit_size_filter narrows which units are checked" do
    rule = alert_rules(:price_threshold_rule)
    # `rule.update!(unit_size_filter: "10x10")` writes a new value to this
    # rule's `unit_size_filter` column, restricting it to only match units
    # of size "10x10" — which excludes the fixture unit
    # (current_mesa_10x15, $90) that would otherwise trip this rule's $100
    # threshold.
    rule.update!(unit_size_filter: "10x10") # excludes the $90 10x15 unit that would otherwise trigger it
    AlertRule.where.not(id: rule.id).update_all(active: false)

    AlertCheckerJob.perform_now(crawl_run_id: crawl_runs(:current_completed).id)

    # Confirms the rule did NOT fire — proving unit_size_filter really did
    # exclude the 10x15 unit that would have matched the threshold.
    assert_nil rule.reload.last_triggered_at
  end
  # `end` closes the "unit_size_filter narrows..." test block above.
end
# `end` closes the `class AlertCheckerJobTest < ActiveSupport::TestCase`
# definition that started at the top of this file.
