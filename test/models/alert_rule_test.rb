# `require "test_helper"` loads test/test_helper.rb before anything else in
# this file runs. That file boots the whole Rails app in "test" mode, loads
# Minitest (Ruby's built-in automated-testing framework — more on that
# below), and sets up shared test configuration (like fixtures — see the
# explanation a few lines down). Every test file in this app starts with
# this same line for that reason.
require "test_helper"

# "Automated testing" means writing code that runs your OTHER code and
# checks the results are what you expect, automatically, instead of a human
# manually clicking around the app to check it still works. This class is
# one such test SUITE (a group of related tests) for the AlertRule model
# (see app/models/alert_rule.rb).
#
# `class AlertRuleTest < ActiveSupport::TestCase` defines a Ruby class named
# AlertRuleTest that inherits from ActiveSupport::TestCase — Rails' base
# class for tests that don't need a real HTTP request/response cycle (unlike
# controller/integration tests). Inheriting from it is what makes the
# `test "..." do ... end` syntax below available, along with fixture access
# (e.g. `alert_rules(:price_drop_rule)`) and all the `assert_*`/`refute_*`
# methods used throughout this file.
class AlertRuleTest < ActiveSupport::TestCase
  # A plain, ordinary Ruby instance method (nothing test-framework-specific
  # about it) that every test below can call to get a fresh Hash of
  # attributes that would build a VALID AlertRule. Defining it once here
  # avoids repeating this same Hash in every single test.
  def valid_attributes
    # A Ruby Hash literal (`{ key: value, ... }`) — this single line builds
    # and returns one Hash with five key/value pairs. Because this is the
    # last (and only) line in the method body, its value is what the method
    # returns — Ruby methods return whatever their last expression evaluates
    # to, no explicit `return` needed. `name:`, `trigger_type:`, etc. are
    # Ruby symbols (lightweight, immutable labels written with a leading
    # colon) used here as Hash keys, matching the column/attribute names on
    # the AlertRule model.
    { name: "Test rule", trigger_type: "price_threshold", threshold_price: 100, email_enabled: true, email_address: "x@example.com" }
  end
  # `end` closes the `def valid_attributes` method definition above.

  # `test "requires a name" do ... end` is special Rails/Minitest syntax
  # (from ActiveSupport::Testing::Declarative, mixed into ActiveSupport::
  # TestCase) that defines one individual automated test, named by the given
  # string. Under the hood it turns the string into a method name (like
  # `test_requires_a_name`) and the block becomes that method's body — when
  # you run the test suite (e.g. `bin/rails test`), every one of these
  # blocks runs on its own, and the suite reports which ones passed or
  # failed.
  test "requires a name" do
    # `AlertRule.new(...)` builds a new, UNSAVED AlertRule object in memory
    # (no database write happens yet). `valid_attributes.merge(name: "")`
    # calls the helper method above to get the base valid Hash, then
    # `.merge(name: "")` returns a NEW Hash with the `name:` key overwritten
    # to an empty string (the original Hash from valid_attributes is left
    # unchanged) — this is how many tests below build a mostly-valid record
    # with just ONE thing deliberately wrong, to check that specific
    # validation catches it.
    rule = AlertRule.new(valid_attributes.merge(name: ""))
    # `refute` is Minitest's assertion for "I expect this to be false (or
    # nil)" — the opposite of `assert`. `rule.valid?` runs all of the
    # AlertRule model's validations (see app/models/alert_rule.rb) against
    # this in-memory object and returns true/false; `refute rule.valid?`
    # fails this test loudly unless `rule.valid?` actually returns false —
    # i.e. this line is checking "a blank name should make the record
    # invalid."
    refute rule.valid?
    # `rule.errors` is populated as a side effect of calling `.valid?`
    # above — it's a collection of validation failure messages, keyed by
    # attribute. `rule.errors[:name]` returns an ARRAY of every error
    # message attached to the `:name` field specifically (there could be
    # more than one). `assert_includes collection, item` is a Minitest
    # assertion checking that `item` appears somewhere in `collection` —
    # here, that the exact custom message from the model's presence
    # validation is among name's error messages.
    assert_includes rule.errors[:name], "Alert name is required"
  end
  # `end` closes this `test "requires a name" do` block.

  test "trigger_type must be price_drop or price_threshold" do
    # Same pattern as above: start from a valid Hash, override just
    # `trigger_type` to an invalid value not in the model's allowed list.
    rule = AlertRule.new(valid_attributes.merge(trigger_type: "bogus"))
    refute rule.valid?
    # Confirms the specific error message from AlertRule's `inclusion:`
    # validation on trigger_type shows up in the errors for that field.
    assert_includes rule.errors[:trigger_type], "Trigger type must be 'price_drop' or 'price_threshold'"
  end
  # `end` closes this `test` block.

  test "threshold_price is required for price_threshold rules" do
    # Overrides two keys at once inside one `.merge(...)` call — Hash#merge
    # accepts as many key/value pairs as you like. This builds a rule whose
    # trigger_type IS "price_threshold" (which the model requires a
    # threshold_price for) but with threshold_price explicitly set to nil.
    rule = AlertRule.new(valid_attributes.merge(trigger_type: "price_threshold", threshold_price: nil))
    refute rule.valid?
    assert_includes rule.errors[:threshold_price], "Threshold price is required when using price threshold trigger"
  end
  # `end` closes this `test` block.

  test "threshold_price is not required for price_drop rules" do
    # This time trigger_type is "price_drop" instead — the model's
    # conditional validation (`if: -> { trigger_type == "price_threshold" }`
    # in app/models/alert_rule.rb) means threshold_price is allowed to be
    # nil in this case, so the record SHOULD be valid.
    rule = AlertRule.new(valid_attributes.merge(trigger_type: "price_drop", threshold_price: nil))
    # `assert` is Minitest's basic "I expect this to be true" check — it
    # fails the test unless its first argument is truthy. The SECOND
    # argument here, `rule.errors.full_messages.join(", ")`, is the failure
    # message Minitest will print if the assertion fails — that's
    # `full_messages` (every validation error as a complete readable
    # sentence, e.g. "Name can't be blank") turned into one comma-separated
    # string via `.join(", ")`. This makes a failing test much easier to
    # debug: instead of just "expected truthy, got false," you'd see exactly
    # which validation(s) unexpectedly failed.
    assert rule.valid?, rule.errors.full_messages.join(", ")
  end
  # `end` closes this `test` block.

  test "threshold_price must be greater than 0 when present" do
    # Overrides threshold_price to a negative number, which the model's
    # `numericality: { greater_than: 0 }` validation should reject.
    rule = AlertRule.new(valid_attributes.merge(threshold_price: -5))
    refute rule.valid?
    assert_includes rule.errors[:threshold_price], "Threshold price must be greater than $0"
  end
  # `end` closes this `test` block.

  test "requires at least one delivery method enabled" do
    # Turns off all three delivery channels (email/discord/sms) at once,
    # which should trip the model's custom `at_least_one_delivery_method`
    # validation (see app/models/alert_rule.rb).
    rule = AlertRule.new(valid_attributes.merge(email_enabled: false, discord_enabled: false, sms_enabled: false))
    refute rule.valid?
    # `:base` is a special error key (not tied to one specific attribute)
    # used for validations that span multiple fields — this reads the
    # errors attached to the record as a whole, rather than to one column.
    assert_includes rule.errors[:base], "At least one delivery method (Email, Discord, or SMS) must be enabled"
  end
  # `end` closes this `test` block.

  test "active scope only returns active rules" do
    # `alert_rules(:price_drop_rule)` looks up a FIXTURE — a pre-made, fake
    # database row defined in test/fixtures/alert_rules.yml (a YAML file
    # under test/fixtures/), automatically loaded into the test database
    # before every single test runs (see the `fixtures :all` line in
    # test/test_helper.rb). `alert_rules(...)` (a method whose name matches
    # the fixture file's name, generated by Rails) takes a Symbol matching
    # one of the labels defined in that YAML file — here, `:price_drop_rule`
    # — and returns the real, saved AlertRule database record built from
    # that fixture's data. Fixtures exist so tests can work with realistic,
    # already-saved records without every test having to hand-build and
    # save its own data first.
    #
    # `AlertRule.active` calls the `active` scope defined in
    # app/models/alert_rule.rb (`where(active: true)`) — a query for every
    # currently-active rule. `assert_includes` checks that the
    # price_drop_rule fixture (which has `active: true` in the YAML — see
    # test/fixtures/alert_rules.yml) shows up in that query's results.
    assert_includes AlertRule.active, alert_rules(:price_drop_rule)
    # `refute_includes` is the opposite of `assert_includes` — it fails
    # unless the given item is ABSENT from the collection. Confirms the
    # inactive_rule fixture (`active: false` in the YAML) is correctly
    # excluded from the `active` scope's results.
    refute_includes AlertRule.active, alert_rules(:inactive_rule)
  end
  # `end` closes this `test` block.

  test "matches_unit? for price_threshold fires at or below the threshold" do
    # Loads the price_threshold_rule fixture. The trailing `# threshold
    # $100` is an ordinary Ruby inline comment left by whoever wrote this
    # test, noting the fixture's threshold_price value for readers (see
    # test/fixtures/alert_rules.yml — that fixture's threshold_price is
    # indeed 100.00).
    rule = alert_rules(:price_threshold_rule) # threshold $100

    # `Unit.new(...)` builds three separate, unsaved Unit objects in memory
    # (see app/models/unit.rb), each with a different `monthly_price` to
    # probe the boundary of the "at or below the threshold" rule.
    # `facility: facilities(:mesa_extra_space)` uses ANOTHER fixture lookup
    # — this time from test/fixtures/facilities.yml — to satisfy Unit's
    # `belongs_to :facility` requirement (a Unit needs a real, associated
    # Facility object even when it's never actually saved to the database
    # here, since `matches_unit?` reads `unit.facility.company` internally).
    cheap_unit = Unit.new(monthly_price: 90, facility: facilities(:mesa_extra_space))
    at_threshold_unit = Unit.new(monthly_price: 100, facility: facilities(:mesa_extra_space))
    expensive_unit = Unit.new(monthly_price: 150, facility: facilities(:mesa_extra_space))

    # `rule.matches_unit?(cheap_unit)` calls the matches_unit? instance
    # method on AlertRule (see app/models/alert_rule.rb) — for a
    # price_threshold rule, it returns true when the unit's best_price is
    # at or below threshold_price. `assert rule.matches_unit?(cheap_unit)`
    # fails the test unless that call returns something truthy.
    assert rule.matches_unit?(cheap_unit)
    # $100 is exactly the threshold — the model's condition uses `<=`
    # (less-than-OR-EQUAL), so this boundary case should also match.
    assert rule.matches_unit?(at_threshold_unit)
    # $150 is above the $100 threshold, so this should NOT match — `refute`
    # fails the test unless the call returns false/nil.
    refute rule.matches_unit?(expensive_unit)
  end
  # `end` closes this `test` block.

  test "matches_unit? for price_drop fires only when the price actually dropped" do
    rule = alert_rules(:price_drop_rule)
    unit = Unit.new(monthly_price: 90, facility: facilities(:mesa_extra_space))

    # For a "price_drop" rule, matches_unit? takes an optional
    # `previous_price:` keyword argument to compare against. Passing 100
    # here means "this unit used to cost $100" — since the unit's current
    # price (90) is lower, the price dropped, so this should match.
    assert rule.matches_unit?(unit, previous_price: 100)
    # Previous price of 80 is LOWER than the current 90 — the price went UP,
    # not down, so this should NOT match.
    refute rule.matches_unit?(unit, previous_price: 80)
    # With no previous_price to compare against (nil), there's nothing to
    # measure a "drop" from — the model's guard clause
    # (`return false if previous_price.nil? || ...`) means this can never
    # match.
    refute rule.matches_unit?(unit, previous_price: nil)
  end
  # `end` closes this `test` block.

  test "matches_unit? respects company_filter and unit_size_filter" do
    rule = alert_rules(:price_threshold_rule)
    # Sets the `company_filter` attribute directly on the in-memory fixture
    # object (this change is NOT saved to the database — it only affects
    # this local `rule` variable for the rest of this test) to restrict the
    # rule to one specific storage company.
    rule.company_filter = "Extra Space Storage"

    # Two Unit objects with the SAME price but DIFFERENT facilities —
    # mesa_extra_space (company: "Extra Space Storage", per
    # test/fixtures/facilities.yml) and gilbert_public_storage (company:
    # "Public Storage") — to test that the company_filter correctly
    # distinguishes between them.
    matching_unit = Unit.new(monthly_price: 90, facility: facilities(:mesa_extra_space))
    other_company_unit = Unit.new(monthly_price: 90, facility: facilities(:gilbert_public_storage))

    # The unit's facility company ("Extra Space Storage") matches the
    # rule's company_filter, so this should match.
    assert rule.matches_unit?(matching_unit)
    # The unit's facility company ("Public Storage") does NOT match the
    # filter, so this should be rejected regardless of price.
    refute rule.matches_unit?(other_company_unit)
  end
  # `end` closes this `test` block.

  test "description summarizes the rule" do
    rule = alert_rules(:price_threshold_rule)
    # `assert_match(pattern, string)` is a Minitest assertion checking that
    # a Regexp (regular expression — a pattern for matching text) matches
    # somewhere inside the given string. `/Price drops below \$100/` is a
    # Ruby Regexp literal (text between `/ /` slashes): it matches the
    # literal text "Price drops below $100" — the `\$` is an "escaped"
    # dollar sign, needed because `$` normally has special meaning in
    # regular expressions (it means "end of line"), so `\$` tells Ruby to
    # treat it as a literal dollar-sign character instead.
    # `rule.description` calls the description instance method on AlertRule
    # (see app/models/alert_rule.rb), which builds a human-readable summary
    # sentence for this rule.
    assert_match(/Price drops below \$100/, rule.description)
    # Checks the description also mentions "Discord" — this fixture has
    # `discord_enabled: true` in test/fixtures/alert_rules.yml, so the
    # description's delivery-channel summary should include it.
    assert_match(/Discord/, rule.description)
  end
  # `end` closes this `test` block.

  test "cooldown_minutes must be zero or a positive whole number" do
    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: -5))
    refute rule.valid?
    assert_includes rule.errors[:cooldown_minutes], "Cooldown must be a whole number of minutes (0 or more)"

    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: 1.5))
    refute rule.valid?
    assert_includes rule.errors[:cooldown_minutes], "Cooldown must be a whole number of minutes (0 or more)"

    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: 0))
    assert rule.valid?, rule.errors.full_messages.join(", ")
  end
  # `end` closes this `test` block.

  test "in_cooldown? is false when cooldown_minutes is zero, regardless of last_triggered_at" do
    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: 0, last_triggered_at: Time.current))
    refute rule.in_cooldown?
  end
  # `end` closes this `test` block.

  test "in_cooldown? is false when the rule has never triggered" do
    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: 60, last_triggered_at: nil))
    refute rule.in_cooldown?
  end
  # `end` closes this `test` block.

  test "in_cooldown? is true while still inside the cooldown window" do
    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: 60, last_triggered_at: 10.minutes.ago))
    assert rule.in_cooldown?
  end
  # `end` closes this `test` block.

  test "in_cooldown? is false once the cooldown window has elapsed" do
    rule = AlertRule.new(valid_attributes.merge(cooldown_minutes: 60, last_triggered_at: 90.minutes.ago))
    refute rule.in_cooldown?
  end
  # `end` closes this `test` block.

  test "description mentions the cooldown window only when one is set" do
    rule = alert_rules(:price_threshold_rule)
    refute_match(/at most once per/, rule.description)

    rule.cooldown_minutes = 30
    assert_match(/at most once per 30min/, rule.description)
  end
  # `end` closes this `test` block.

  test "record_triggered! stamps last_triggered_at" do
    rule = alert_rules(:price_drop_rule)
    # `assert_nil` is a Minitest assertion checking its argument is exactly
    # `nil`. The price_drop_rule fixture never sets last_triggered_at in its
    # YAML, so it should start out nil (this rule has never fired yet).
    assert_nil rule.last_triggered_at

    # Calls the record_triggered! instance method (see
    # app/models/alert_rule.rb), which writes the current time into the
    # last_triggered_at column via `update_column` — a direct database
    # write, bypassing validations/callbacks.
    rule.record_triggered!
    # `rule.reload` re-fetches this record's attributes fresh FROM THE
    # DATABASE, discarding any stale in-memory values — necessary here
    # because `update_column` (used inside record_triggered!) writes
    # straight to the database without updating Ruby-side attributes that
    # Rails might have cached differently, so reloading guarantees we're
    # checking what's actually now stored. `assert_not_nil` is the opposite
    # of `assert_nil` — it fails unless the value is anything other than
    # nil, confirming last_triggered_at now holds a real timestamp.
    assert_not_nil rule.reload.last_triggered_at
  end
  # `end` closes this `test` block.
end
# `end` closes the `class AlertRuleTest < ActiveSupport::TestCase` block
# that started at the top of this file.
