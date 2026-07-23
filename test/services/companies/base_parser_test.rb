# `require "test_helper"` loads test/test_helper.rb, which boots Rails in
# test mode and loads the fixture data used below (crawl_runs, facilities).
require "test_helper"

# BaseParser is abstract (company_name/company_slug/etc. raise
# NotImplementedError) and its browser-facing methods (open_page,
# take_error_screenshot, parse_locations, parse_units) need a real
# Playwright page — not something to fake convincingly in a unit test. This
# covers the pure, browser-independent shared logic every company parser
# inherits: price/size parsing, filtering, and the Facility upsert logic.
#
# `class TestParser < Companies::BaseParser` defines a MINIMAL concrete
# subclass of Companies::BaseParser (app/services/companies/base_parser.rb)
# purely for testing purposes — it's not a real company parser used by the
# app, it exists ONLY in this test file so BaseParser's shared/protected
# methods (tested below) can actually be exercised on a real instance,
# since BaseParser itself can't be instantiated usefully on its own (its
# abstract methods would raise NotImplementedError if called).
class TestParser < Companies::BaseParser
  # `def company_name = "Test Co"` is Ruby's single-line "endless method"
  # syntax (available since Ruby 3.0) — equivalent to writing
  # `def company_name; "Test Co"; end` but on one line, with the `=`
  # marking where the method body starts. This overrides BaseParser's
  # abstract `company_name` (which normally raises NotImplementedError) so
  # TestParser has a real, harmless value to return instead.
  def company_name = "Test Co"
  # Same idea — overrides company_slug, used in log tags and screenshot
  # filenames, with a fixed placeholder value.
  def company_slug = "test_co"
  # Overrides search_url. It ignores its three parameters (`lat`, `lng`,
  # `radius_miles` — accepted but unused, since this test class never
  # actually needs to build a real search URL) and always returns the same
  # fake URL string.
  def search_url(lat, lng, radius_miles) = "https://example.com/search"
  # Overrides parse_locations to always return an empty Array — fine here
  # because none of the tests below call `.run` (BaseParser's real
  # browser-driving entry point), only the individual protected helper
  # methods directly.
  def parse_locations(page) = []
  # Overrides parse_units the same way, also always returning an empty Array.
  def parse_units(page, facility) = []
end
# `end` closes the `class TestParser < Companies::BaseParser` definition above.

# `class BaseParserTest < ActiveSupport::TestCase` — the actual test class
# for this file, using TestParser (defined above) as its test subject.
class BaseParserTest < ActiveSupport::TestCase
  # `def parser(options: {})` defines a helper method (with a keyword
  # argument that defaults to an empty Hash) that builds a fresh TestParser
  # instance for a test to use. Defining this once here avoids repeating
  # the same `TestParser.new(...)` call in every single test below.
  def parser(options: {})
    # `TestParser.new(crawl_run:, browser:, options:)` matches
    # Companies::BaseParser#initialize's required keyword arguments (see
    # app/services/companies/base_parser.rb). `crawl_runs(:current_completed)`
    # is a fixture lookup. `browser: Object.new` passes in a plain, generic
    # Ruby Object as a stand-in "browser" — good enough here because none
    # of the tests below actually call methods that would need a real
    # Playwright browser object (like `open_page`), only ones that work on
    # plain Ruby data (strings, hashes).
    TestParser.new(crawl_run: crawl_runs(:current_completed), browser: Object.new, options: options)
  end
  # `end` closes the `def parser` helper method definition above.

  test "parse_price extracts a decimal from various formats" do
    # `p = parser` calls the helper method above (with default empty
    # options) and stores the resulting TestParser instance in a local
    # variable for this test to use.
    p = parser
    # `p.send(:parse_price, "$89.00/mo")` — `parse_price` is a PROTECTED
    # method on BaseParser (see the "protected" keyword partway through
    # app/services/companies/base_parser.rb), meaning it can normally only
    # be called from other code inside the same class or its subclasses —
    # not directly from outside code like this test. `.send(...)` is
    # Ruby's way of calling ANY method (public, protected, or private) by
    # name, bypassing that visibility restriction — a common trick in
    # tests that need to exercise internal helper logic directly without
    # going through the full public `.run` method. Here it confirms
    # `parse_price` strips the "$", "/mo" and converts to a numeric 89.0.
    assert_equal 89.0, p.send(:parse_price, "$89.00/mo")
    # Confirms a plain numeric string with no symbols parses the same way.
    assert_equal 89.0, p.send(:parse_price, "89")
    # Confirms a price with a thousands-separator comma parses correctly
    # too (the comma gets stripped along with "$").
    assert_equal 1234.5, p.send(:parse_price, "$1,234.50")
  end
  # `end` closes the "parse_price extracts a decimal..." test block above.

  test "parse_price returns nil for blank or zero prices" do
    p = parser
    # `assert_nil p.send(:parse_price, nil)` confirms passing Ruby's `nil`
    # (representing "no value at all") returns nil back out, rather than
    # raising an error.
    assert_nil p.send(:parse_price, nil)
    # An empty string is also treated as "no price" and returns nil.
    assert_nil p.send(:parse_price, "")
    # "$0" parses to a numeric zero, which parse_price explicitly treats as
    # "not a real price" (see the `return nil if price <= 0` line in
    # base_parser.rb) and returns nil for.
    assert_nil p.send(:parse_price, "$0")
    # Text with no digits at all in it (after stripping non-numeric
    # characters, nothing remains) also returns nil rather than crashing.
    assert_nil p.send(:parse_price, "call for pricing")
  end
  # `end` closes the "parse_price returns nil for blank or zero prices" test block above.

  test "parse_size normalizes various size formats to WIDTHxDEPTH" do
    p = parser
    # Confirms an already-normalized "10x20" string parses to itself
    # unchanged.
    assert_equal "10x20", p.send(:parse_size, "10x20")
    # Confirms a format with quote marks (for feet) and spaces around "x"
    # still normalizes to the same plain "10x20" result.
    assert_equal "10x20", p.send(:parse_size, "10' x 20'")
    # Confirms uppercase "X" and a trailing "ft" unit label are handled the
    # same way, since parse_size only extracts the digit groups and
    # discards everything else (see base_parser.rb's use of `.scan(/\d+/)`).
    assert_equal "10x20", p.send(:parse_size, "10 X 20 ft")
  end
  # `end` closes the "parse_size normalizes various size formats..." test block above.

  test "parse_size returns nil when it can't find two numbers" do
    p = parser
    assert_nil p.send(:parse_size, nil)
    assert_nil p.send(:parse_size, "")
    # The word "large" contains no digits at all, so parse_size can't find
    # even one number, let alone the two (width and depth) it needs — it
    # returns nil rather than raising.
    assert_nil p.send(:parse_size, "large")
  end
  # `end` closes the "parse_size returns nil when it can't find two
  # numbers" test block above.

  test "apply_filters drops units smaller than the 10x10 minimum" do
    p = parser
    # `units = [ { size: "5x5", unit_type: "standard", climate_controlled: true } ]`
    # builds a one-element Array containing a Hash of raw unit attributes,
    # shaped like what a real company parser's `parse_units` would return
    # before filtering. A 5x5 unit is smaller than BaseParser's hardcoded
    # 10x10 minimum (see the `min_width`/`min_depth` check inside
    # apply_filters in base_parser.rb).
    units = [ { size: "5x5", unit_type: "standard", climate_controlled: true } ]
    # `p.send(:apply_filters, units)` calls the protected apply_filters
    # method directly (bypassing its normal visibility via `.send`, as
    # above). `assert_empty` passes only if the returned Array has zero
    # elements — confirming the too-small unit was filtered out.
    assert_empty p.send(:apply_filters, units)
  end
  # `end` closes the "apply_filters drops units smaller than the 10x10
  # minimum" test block above.

  test "apply_filters drops excluded unit types" do
    p = parser
    # `unit_type: "parking"` — BaseParser's default `Unit::EXCLUDED_TYPES`
    # list (referenced inside apply_filters when no `options[:excluded_types]`
    # override is given) includes types like "parking" that should never
    # be surfaced as storage units.
    units = [ { size: "10x10", unit_type: "parking", climate_controlled: true } ]
    assert_empty p.send(:apply_filters, units)
  end
  # `end` closes the "apply_filters drops excluded unit types" test block above.

  test "apply_filters requires climate control only when that option is set" do
    # `parser(options: { climate_controlled: true })` calls the `parser`
    # helper method with an explicit `options:` Hash this time (overriding
    # its default empty Hash), turning ON the "must be climate controlled"
    # filter for this one test.
    p = parser(options: { climate_controlled: true })
    # This unit is explicitly NOT climate controlled, so with the option
    # above turned on, apply_filters should reject it.
    units = [ { size: "10x10", unit_type: "standard", climate_controlled: false } ]
    assert_empty p.send(:apply_filters, units)
  end
  # `end` closes the "apply_filters requires climate control only when that
  # option is set" test block above.

  test "apply_filters buckets non-standard sizes into the closest selected size" do
    # `options: { sizes: [ "10x10" ] }` restricts the filter to only allow
    # units that "bucket" into the 10x10 standard size (see BaseParser's
    # size_bucket method, which maps arbitrary real-world sizes to the
    # closest standard size by square footage).
    p = parser(options: { sizes: [ "10x10" ] })
    # 10x12 (120 sqft) is closer to 10x10 (100 sqft) than 10x15 (150 sqft)
    units = [ { size: "10x12", unit_type: "standard", climate_controlled: false } ]
    result = p.send(:apply_filters, units)
    # `assert_equal 1, result.length` confirms the 10x12 unit was KEPT
    # (bucketed into "10x10", which the options above selected), unlike the
    # earlier tests where units were dropped entirely.
    assert_equal 1, result.length
  end
  # `end` closes the "apply_filters buckets non-standard sizes..." test block above.

  test "apply_filters keeps drive-up/outdoor units (no UI control excludes them here)" do
    p = parser
    # `drive_up: true` is an extra key in the unit Hash beyond the ones
    # other tests use. Per the comment kept from the original test and the
    # matching comment inside base_parser.rb's apply_filters method, there
    # is intentionally no filter option that excludes drive-up/outdoor
    # units — this test documents that "on purpose" behavior so a future
    # change that accidentally started dropping them would break this test.
    units = [ { size: "10x10", unit_type: "standard", climate_controlled: false, drive_up: true } ]
    assert_equal 1, p.send(:apply_filters, units).length
  end
  # `end` closes the "apply_filters keeps drive-up/outdoor units..." test block above.

  test "upsert_facility matching is scoped to the parser's own company" do
    p = parser
    # `facilities(:gilbert_public_storage)` looks up a Facility fixture
    # (test/fixtures/facilities.yml) whose `company` column is "Public
    # Storage" — a DIFFERENT company name than TestParser's own
    # `company_name` ("Test Co", defined at the top of this file).
    existing = facilities(:gilbert_public_storage) # company: "Public Storage"

    # `p.send(:upsert_facility, { ... })` calls the protected upsert_facility
    # method with a Hash of location data that reuses the EXISTING
    # facility's address/city/state/zip/external_id — everything matches
    # except the company (implicitly "Test Co", since that's what this
    # parser's own company_name returns and upsert_facility scopes its
    # database lookup by that).
    found = p.send(:upsert_facility, {
      name: "Renamed", address: existing.address, city: existing.city,
      state: existing.state, zip: existing.zip, external_id: existing.external_id
    })

    # upsert_facility scopes by the parser's own company_name ("Test Co"),
    # so a matching external_id under a DIFFERENT company creates a new
    # record rather than reusing (and silently renaming) the other one.
    # `assert_equal "Test Co", found.company` confirms the newly
    # created/found Facility really does belong to "Test Co", not "Public
    # Storage".
    assert_equal "Test Co", found.company
    # `refute_equal existing.id, found.id` confirms this is a genuinely
    # DIFFERENT database row than the existing Public Storage facility —
    # proving upsert_facility didn't accidentally match/reuse (and thus
    # corrupt) the other company's record.
    refute_equal existing.id, found.id
  end
  # `end` closes the "upsert_facility matching is scoped to the parser's
  # own company" test block above.

  test "upsert_facility updates an existing record on a second call with the same external_id" do
    p = parser
    # `location_data` holds a Hash of fresh, made-up facility attributes
    # with a unique made-up `external_id`, used as the "identity key" for
    # matching in both calls below.
    location_data = {
      name: "First Name", address: "1 Test St", city: "Testville", state: "AZ",
      zip: "85000", external_id: "unique-123"
    }

    # First call: no existing Facility with this external_id + company
    # exists yet, so upsert_facility creates a brand new row.
    first  = p.send(:upsert_facility, location_data)
    # Second call: `location_data.merge(name: "Updated Name")` builds a NEW
    # Hash that's a copy of location_data but with `name` overridden — the
    # original `location_data` Hash itself is left unchanged (`.merge`
    # returns a new Hash rather than mutating the original). Passing this
    # (same external_id, different name) should find and UPDATE the
    # existing row rather than creating a second one.
    second = p.send(:upsert_facility, location_data.merge(name: "Updated Name"))

    # `assert_equal first.id, second.id` confirms both calls returned the
    # SAME database row (same primary key) — proving it was an update, not
    # an accidental duplicate insert.
    assert_equal first.id, second.id
    # `second.reload.name` re-fetches the row from the database (rather
    # than trusting the in-memory Ruby object, which could theoretically be
    # stale) to confirm the name really was updated to "Updated Name" in
    # the database itself.
    assert_equal "Updated Name", second.reload.name
  end
  # `end` closes the "upsert_facility updates an existing record..." test block above.

  test "upsert_facility raises with a clear message when the facility is invalid" do
    p = parser
    # `assert_raises(RuntimeError) do ... end` is a Minitest assertion that
    # runs the block and PASSES only if it raises an exception of exactly
    # this class (or a subclass) — and FAILS if the block either raises
    # nothing at all, or raises some other, different kind of exception.
    # The raised exception object itself is also returned by
    # `assert_raises`, captured here into the local variable `error`.
    error = assert_raises(RuntimeError) do
      # This Hash is deliberately missing an `address:` key — Facility
      # presumably validates that address is required (see
      # app/models/facility.rb), so `facility.save` inside upsert_facility
      # should fail, triggering the `raise "Could not save facility..."`
      # line in base_parser.rb.
      p.send(:upsert_facility, { name: "No address", city: "Testville", state: "AZ", zip: "85000" })
    end
    # `end` closes the `assert_raises(RuntimeError) do` block above.
    # `assert_match(/Could not save facility/, error.message)` confirms the
    # raised exception's message text (accessed via `.message`, a standard
    # method every Ruby exception object has) actually explains what went
    # wrong, rather than being some generic/unhelpful error.
    assert_match(/Could not save facility/, error.message)
  end
  # `end` closes the "upsert_facility raises with a clear message..." test block above.

  test "save_unit persists a unit associated with the facility and crawl run" do
    p = parser
    facility = facilities(:gilbert_public_storage)

    # `p.send(:save_unit, { size:, monthly_price:, collected_at: }, facility)`
    # calls the protected save_unit method directly, passing a Hash of raw
    # unit attributes plus the Facility record it belongs to.
    unit = p.send(:save_unit, { size: "10x10", monthly_price: 100, collected_at: Time.current }, facility)

    # `unit.persisted?` is a standard ActiveRecord method returning true
    # only if this record has actually been saved to the database (as
    # opposed to just built in memory and never saved, or saved and then
    # deleted). Confirms save_unit really did call `.save` successfully.
    assert unit.persisted?
    # Confirms the saved Unit's `facility` association points back to the
    # exact Facility object passed in.
    assert_equal facility, unit.facility
    # Confirms the saved Unit's `crawl_run` association was set to the
    # CrawlRun the parser itself was built with (`crawl_runs(:current_completed)`,
    # set inside the `parser` helper method at the top of this file) — this
    # is what lets every unit from one crawl run be traced back to it later.
    assert_equal crawl_runs(:current_completed), unit.crawl_run
  end
  # `end` closes the "save_unit persists a unit associated with the
  # facility and crawl run" test block above.
end
# `end` closes the `class BaseParserTest < ActiveSupport::TestCase`
# definition that started earlier in this file.
