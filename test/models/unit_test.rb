# Loads test/test_helper.rb, which boots the Rails app in test mode and sets
# up shared test infrastructure (Minitest, fixture loading, etc.). See
# test/test_helper.rb or test/models/alert_rule_test.rb for a fuller
# explanation of what this line does.
require "test_helper"

# An automated test suite for the Unit model (see app/models/unit.rb) — a
# Unit represents one type of storage unit at a specific facility.
# `class UnitTest < ActiveSupport::TestCase` inherits from Rails' base test
# class, providing the `test "..." do ... end` syntax below, the
# `assert_*`/`refute_*` assertion methods, and fixture lookups like
# `units(:...)`/`facilities(:...)`/`crawl_runs(:...)`.
class UnitTest < ActiveSupport::TestCase
  # A plain Ruby helper method (not a test itself) returning a Hash of
  # attributes that build a VALID Unit, so individual tests below don't
  # each need to repeat this setup.
  def valid_attributes
    # A multi-line Hash literal — `{`, then one `key: value,` pair per line,
    # then the closing `}` — Ruby doesn't require the line breaks, this is
    # purely a readability choice for a Hash with several entries.
    {
      # `facilities(:gilbert_public_storage)` and `crawl_runs(:current_completed)`
      # are FIXTURE lookups: fixtures are pre-made, fake database rows
      # defined in YAML files under test/fixtures/ (here,
      # test/fixtures/facilities.yml and test/fixtures/crawl_runs.yml),
      # automatically loaded into the test database before every test runs.
      # These satisfy Unit's `belongs_to :facility` and `belongs_to
      # :crawl_run` requirements — every Unit must be linked to a real
      # Facility and a real CrawlRun.
      facility: facilities(:gilbert_public_storage),
      crawl_run: crawl_runs(:current_completed),
      size: "10x10",
      monthly_price: 100,
      # `Time.current` returns the current time in the app's configured
      # time zone (Rails' preferred alternative to plain `Time.now`) —
      # used here to satisfy the model's `presence:` validation on
      # `collected_at` (the timestamp this unit's data was scraped).
      collected_at: Time.current
    }
  end
  # `end` closes the `def valid_attributes` method definition.

  # `test "..." do ... end` defines one individual automated test (see
  # test/models/alert_rule_test.rb for a full explanation of this Rails/
  # Minitest syntax).
  test "requires size and collected_at" do
    # `Unit.new` with no arguments builds a completely blank, unsaved
    # record — every attribute nil, deliberately missing the required
    # `size` and `collected_at` fields (and the required associations, but
    # this test only checks the two presence validations below).
    unit = Unit.new
    # `refute unit.valid?` fails unless `.valid?` (which runs every
    # validation in app/models/unit.rb) actually returns false.
    refute unit.valid?
    # `unit.errors[:size]` reads the array of error messages attached
    # specifically to the `size` field. `assert_includes array, item`
    # checks that the model's custom presence-validation message is among
    # them.
    assert_includes unit.errors[:size], "Unit size is required (e.g. 10x10)"
    assert_includes unit.errors[:collected_at], "Collection timestamp is required"
  end
  # `end` closes this `test` block.

  test "size must match WIDTHxDEPTH format" do
    # `valid_attributes.merge(size: "not-a-size")` calls the helper method
    # above to get a base valid Hash, then `.merge(size: "not-a-size")`
    # returns a NEW Hash with just `size` overwritten to something that
    # doesn't match the model's `WIDTHxDEPTH` pattern (see the `format:`
    # validation with regex `/\A\d+x\d+\z/i` in app/models/unit.rb).
    unit = Unit.new(valid_attributes.merge(size: "not-a-size"))
    refute unit.valid?
    assert_includes unit.errors[:size], "Size must be in WIDTHxDEPTH format (e.g. 10x10, 10x20)"
  end
  # `end` closes this `test` block.

  test "monthly_price must be greater than 0 when present" do
    # 0 is not GREATER than 0, so this should fail the model's
    # `numericality: { greater_than: 0 }` validation.
    unit = Unit.new(valid_attributes.merge(monthly_price: 0))
    refute unit.valid?
    assert_includes unit.errors[:monthly_price], "Monthly price must be greater than $0"
  end
  # `end` closes this `test` block.

  test "monthly_price may be nil" do
    # The model's price validation uses `allow_nil: true` (see
    # app/models/unit.rb) — a MISSING price is allowed (e.g. a scraper
    # couldn't find one), only an invalid NUMBER (like 0 or negative) is
    # rejected.
    unit = Unit.new(valid_attributes.merge(monthly_price: nil))
    # `assert value, message` — the second argument,
    # `unit.errors.full_messages.join(", ")`, is what Minitest prints if
    # this assertion fails: every validation error as a readable sentence,
    # joined into one string, making a failure easy to diagnose instead of
    # just "expected truthy, got false."
    assert unit.valid?, unit.errors.full_messages.join(", ")
  end
  # `end` closes this `test` block.

  test "parses width/depth/sqft from size before saving" do
    # `Unit.create!(...)` both builds AND saves a new Unit in one step
    # (unlike `.new`, which only builds it in memory). Saving is important
    # here because the width/depth/sqft parsing happens inside a
    # `before_save` callback (`parse_dimensions`, see app/models/unit.rb) —
    # it only runs when an actual save is attempted, so `.new` alone
    # wouldn't trigger it. The `!` means this raises an error if validation
    # fails rather than silently returning false.
    unit = Unit.create!(valid_attributes.merge(size: "10x20"))
    # After saving, `parse_dimensions` should have split "10x20" into
    # width_ft: 10 and depth_ft: 20, and computed sqft as their product.
    assert_equal 10, unit.width_ft
    assert_equal 20, unit.depth_ft
    assert_equal 200, unit.sqft
  end
  # `end` closes this `test` block.

  test "best_price prefers the web special when it's cheaper" do
    # `Unit.new(monthly_price: 150, web_special_price: 99)` builds an
    # unsaved record with only these two attributes set — enough to
    # exercise `best_price` (see app/models/unit.rb), which doesn't depend
    # on any other field. `assert_equal expected, actual` fails unless the
    # two values are exactly equal.
    unit = Unit.new(monthly_price: 150, web_special_price: 99)
    # The web special (99) is cheaper than the regular price (150), so
    # best_price should prefer it.
    assert_equal 99, unit.best_price
  end
  # `end` closes this `test` block.

  test "best_price falls back to monthly_price when there's no cheaper special" do
    # Here the web special (175) is MORE expensive than the regular price
    # (150) — best_price should ignore the "special" and use the regular
    # price instead, since it's actually the better deal.
    unit = Unit.new(monthly_price: 150, web_special_price: 175)
    assert_equal 150, unit.best_price
  end
  # `end` closes this `test` block.

  test "best_price handles a nil monthly_price" do
    # No regular price at all (nil), but a web special IS present — since
    # there's nothing to compare it against, best_price should just return
    # the web special.
    unit = Unit.new(monthly_price: nil, web_special_price: 99)
    assert_equal 99, unit.best_price

    # Neither price is present — best_price should return nil rather than
    # raising an error (e.g. from calling `.to_d` on a nil monthly_price).
    # `assert_nil` fails unless its argument is exactly `nil`.
    unit2 = Unit.new(monthly_price: nil, web_special_price: nil)
    assert_nil unit2.best_price
  end
  # `end` closes this `test` block.

  test "has_web_special? is true only when the special is cheaper" do
    # `has_web_special?` (see app/models/unit.rb) is true only when a web
    # special is present AND cheaper than the regular price.
    assert Unit.new(monthly_price: 150, web_special_price: 99).has_web_special?
    # A web special that's MORE expensive than the regular price doesn't
    # count as a real "special" — should be false.
    refute Unit.new(monthly_price: 150, web_special_price: 175).has_web_special?
    # No web special at all (nil) — should be false, not an error. Note:
    # app/models/unit.rb flags that this method does NOT explicitly guard
    # against monthly_price itself being nil the way best_price does — see
    # the "flag but don't fix" notes at the end of this task's report for
    # more on that.
    refute Unit.new(monthly_price: 150, web_special_price: nil).has_web_special?
  end
  # `end` closes this `test` block.

  test "formatted_price handles nil" do
    # No monthly_price at all — formatted_price (see app/models/unit.rb)
    # should return the friendly fallback text "Not listed" instead of
    # crashing or showing a blank/garbled price.
    assert_equal "Not listed", Unit.new(monthly_price: nil).formatted_price
    # A real price should be formatted as a dollar amount with exactly two
    # decimal places.
    assert_equal "$89.00", Unit.new(monthly_price: 89).formatted_price
  end
  # `end` closes this `test` block.

  test "price_color_class buckets by best_price" do
    # `price_color_class` (see app/models/unit.rb) returns a CSS class name
    # used to color-code price cells in the dashboard, based on price
    # ranges. No price at all — should be the "unknown" bucket, not an
    # error.
    assert_equal "price-unknown", Unit.new(monthly_price: nil).price_color_class
    # $50 is under $100 — "green" bucket (a good deal).
    assert_equal "price-green",   Unit.new(monthly_price: 50).price_color_class
    # $120 is between $100 and $149 — "yellow" bucket (mid-range).
    assert_equal "price-yellow",  Unit.new(monthly_price: 120).price_color_class
    # $200 is $150 or more — "red" bucket (expensive).
    assert_equal "price-red",     Unit.new(monthly_price: 200).price_color_class
  end
  # `end` closes this `test` block.

  test "matches_default_filters? requires climate control, indoor, non-drive-up, and minimum size" do
    # Builds a Unit with every attribute set to satisfy ALL of
    # `matches_default_filters?`'s conditions at once (see
    # app/models/unit.rb): climate_controlled true, indoor true, drive_up
    # false, a unit_type not in the EXCLUDED_TYPES list ("standard" isn't
    # excluded), and dimensions at/above the minimum (10x10).
    good = Unit.new(
      climate_controlled: true, indoor: true, drive_up: false,
      unit_type: "standard", width_ft: 10, depth_ft: 10
    )
    # This should pass every condition, so matches_default_filters? should
    # be true.
    assert good.matches_default_filters?

    # `.dup` creates a duplicate (shallow copy) of `good`, unsaved and
    # independent — mutating `too_small`'s width below doesn't affect
    # `good`. Shrinking width_ft below the MIN_WIDTH_FT constant (10)
    # should now make the whole check fail (it's a chain of `&&`
    # conditions, so ANY one failing makes the result false).
    too_small = good.dup
    too_small.width_ft = 5
    refute too_small.matches_default_filters?

    # Another duplicate, this time with a unit_type ("parking") that IS in
    # the model's EXCLUDED_TYPES constant — should also fail the check.
    excluded_type = good.dup
    excluded_type.unit_type = "parking"
    refute excluded_type.matches_default_filters?
  end
  # `end` closes this `test` block.

  test "apply_filters scopes by climate control, size, and defaults to available/indoor/non-drive-up" do
    # `Unit.apply_filters(sizes: [ "10x10" ])` calls the class method (see
    # app/models/unit.rb) with a Hash containing just the `sizes:` key — an
    # array with one size string. Besides filtering to that size,
    # apply_filters ALSO applies several filters "by default" unless told
    # otherwise (available-only, indoor-only, exclude drive-up) — this test
    # doesn't override any of those defaults.
    results = Unit.apply_filters(sizes: [ "10x10" ])
    # The current_gilbert_10x10 fixture (see test/fixtures/units.yml) is a
    # 10x10, available, indoor, non-drive-up unit — it should match every
    # filter applied here.
    assert_includes results, units(:current_gilbert_10x10)
    # The current_mesa_10x15 fixture is a 10x15 unit — the WRONG size — so
    # it should be excluded by the `sizes:` filter regardless of matching
    # every other default filter.
    refute_includes results, units(:current_mesa_10x15)
  end
  # `end` closes this `test` block.

  test "all_sizes returns sizes sorted by square footage" do
    # `Unit.all_sizes` (see app/models/unit.rb) returns every distinct size
    # string present in the database, sorted by total square footage
    # (width * depth) rather than plain alphabetical order.
    sizes = Unit.all_sizes
    # This test recomputes the EXPECTED sort order independently (rather
    # than hardcoding a literal expected array), using the same underlying
    # logic in a fresh block, to check the two produce the identical order.
    # `sizes.sort_by { |s| ... }` sorts a COPY of the `sizes` array using
    # the block's return value as each element's sort key.
    # `s.split("x").map(&:to_i)` splits a size string like "10x20" on the
    # literal character "x" into ["10", "20"], then `.map(&:to_i)`
    # (shorthand for `.map { |piece| piece.to_i }`) converts each piece to
    # an integer, e.g. [10, 20]. `.reduce(:*)` multiplies all elements of
    # that array together (width * depth) — `:*` is the multiplication
    # operator symbol, passed to `.reduce` as the operation to repeatedly
    # apply across the array's elements.
    #
    # `assert_equal expected, actual` here checks that `sizes` (already
    # sorted by `Unit.all_sizes` itself) is UNCHANGED by re-sorting it this
    # same way — i.e. it's already in the correct square-footage order.
    assert_equal sizes.sort_by { |s| s.split("x").map(&:to_i).reduce(:*) }, sizes
  end
  # `end` closes this `test` block.
end
# `end` closes the `class UnitTest < ActiveSupport::TestCase` block that
# started at the top of this file.
