# Loads test/test_helper.rb, which boots the Rails app in test mode and sets
# up shared test infrastructure (Minitest, fixture loading, and, notably
# for THIS file, a fake/stubbed Geocoder response so saving a Facility in
# tests never makes a real network request; see test/test_helper.rb for the
# `Geocoder.configure`/`set_default_stub` setup).
require "test_helper"

# An automated test suite for the Facility model (see
# app/models/facility.rb). `class FacilityTest < ActiveSupport::TestCase`
# inherits from Rails' base test class, providing the `test "..." do ... end`
# syntax below, the `assert_*`/`refute_*` assertion methods, and fixture
# lookups like `facilities(:...)`.
class FacilityTest < ActiveSupport::TestCase
  # `test "..." do ... end` defines one individual automated test (see
  # test/models/alert_rule_test.rb for a full explanation of this Rails/
  # Minitest syntax).
  test "requires company, name, address, city, state, zip" do
    # `Facility.new` with NO arguments builds a completely blank, unsaved
    # record, every attribute is nil.
    facility = Facility.new
    # `refute facility.valid?`, running `.valid?` triggers every
    # validation in app/models/facility.rb; with everything blank, several
    # `presence:` validations should fail, so `.valid?` should return false.
    refute facility.valid?
    # `%i[company name address city state zip]` is Ruby's "percent-i" array
    # shorthand for an array of SYMBOLS, exactly equivalent to writing
    # `[:company, :name, :address, :city, :state, :zip]`, just less typing.
    # `.each do |attr| ... end` loops over that array, running the block
    # once per symbol, with `attr` holding the current one each time.
    %i[company name address city state zip].each do |attr|
      # `facility.errors.attribute_names` returns an array of every
      # attribute symbol that currently has at least one validation error
      # attached. `assert_includes` checks each attribute in the list above
      # shows up there, i.e. this loop checks ALL SIX required fields
      # produced an error, not just that `.valid?` was false overall.
      assert_includes facility.errors.attribute_names, attr
    end
    # `end` closes the `%i[...].each do |attr|` loop above.
  end
  # `end` closes this `test` block.

  test "zip must be 5 digits or ZIP+4 format" do
    # `facilities(:gilbert_public_storage)` is a FIXTURE lookup: fixtures
    # are pre-made, fake database rows defined in YAML files under
    # test/fixtures/ (here, test/fixtures/facilities.yml), automatically
    # loaded into the test database before every test runs. `.dup` then
    # creates a DUPLICATE, unsaved copy of that record in memory, so this
    # test can freely change its `zip`/`external_id` attributes below
    # without touching the real fixture row other tests might rely on.
    facility = facilities(:gilbert_public_storage).dup

    # The fixture's external_id ("6079") is already used by the original
    # saved row, since this duplicate would otherwise collide with the
    # model's `uniqueness: { scope: :company }` validation on external_id
    # (see app/models/facility.rb) and fail validation for an UNRELATED
    # reason, this line gives the duplicate a different external_id so only
    # the thing actually being tested here (zip format) can affect the
    # result.
    facility.external_id = "unique-zip-test"

    # A plain 5-digit ZIP should be valid.
    facility.zip = "85296"
    # `assert facility.valid?` fails unless `.valid?` returns something
    # truthy.
    assert facility.valid?

    # ZIP+4 format (5 digits, hyphen, 4 more digits) should also be valid.
    facility.zip = "85296-1234"
    assert facility.valid?

    # Neither digit format, should fail the model's `format:` validation.
    facility.zip = "abc"
    refute facility.valid?
    assert_includes facility.errors[:zip], "ZIP must be 5 digits or ZIP+4 format (e.g. 85296)"
  end
  # `end` closes this `test` block.

  test "external_id must be unique per company" do
    existing = facilities(:gilbert_public_storage)
    # `Facility.new(...)` builds a brand-new, unsaved record (not a
    # duplicate of `existing` this time, but a fresh Hash of attributes)
    # that intentionally reuses `existing.external_id` for the SAME company
    # , this should trip the model's uniqueness validation.
    dup = Facility.new(
      company: existing.company, name: "Dup", address: "999 Other Rd",
      city: "Gilbert", state: "AZ", zip: "85296", external_id: existing.external_id
    )

    refute dup.valid?
    assert_includes dup.errors[:external_id], "already has a facility with this external ID for this company"
  end
  # `end` closes this `test` block.

  test "the same external_id is fine for a different company" do
    existing = facilities(:gilbert_public_storage)
    # Reuses the same external_id as `existing`, but with a DIFFERENT
    # `company` value, since the model's uniqueness validation is scoped
    # to `:company` (`scope: :company` in app/models/facility.rb, meaning
    # "unique only among rows for the same company"), this should be
    # allowed.
    other = Facility.new(
      company: "A Totally Different Company", name: "Other", address: "1 Other Rd",
      city: "Gilbert", state: "AZ", zip: "85296", external_id: existing.external_id
    )

    # The second argument here, `other.errors.full_messages.join(", ")`, is
    # the message Minitest prints if this assertion FAILS, turning
    # `full_messages` (every validation error as a readable sentence) into
    # one comma-separated string, so a failure is easy to debug at a
    # glance instead of just saying "expected truthy, got false."
    assert other.valid?, other.errors.full_messages.join(", ")
  end
  # `end` closes this `test` block.

  test "address must be unique per company+city+state when external_id is blank" do
    # `facilities(:no_external_id_facility)` loads a fixture whose
    # `external_id:` is left BLANK in test/fixtures/facilities.yml, the
    # exact case that triggers the model's address-uniqueness validation
    # (`if: -> { external_id.blank? }` in app/models/facility.rb).
    existing = facilities(:no_external_id_facility)
    # Builds a new record reusing `existing`'s address/city/state/company,
    # but with NO external_id given at all (so it stays nil), this should
    # collide with the address-uniqueness rule.
    dup = Facility.new(
      company: existing.company, name: "Dup", address: existing.address,
      city: existing.city, state: existing.state, zip: "85286"
    )

    refute dup.valid?
    assert_includes dup.errors[:address], "already has a facility at this address for this company"
  end
  # `end` closes this `test` block.

  test "duplicate address is fine when external_id is present" do
    existing = facilities(:no_external_id_facility)
    # Same duplicate address/city/state/company as above, but THIS TIME an
    # external_id IS supplied ("some-id"), since the address-uniqueness
    # validation only runs `if external_id.blank?`, supplying one at all
    # skips that check entirely, so this record should be valid despite the
    # matching address.
    dup = Facility.new(
      company: existing.company, name: "Dup", address: existing.address,
      city: existing.city, state: existing.state, zip: "85286", external_id: "some-id"
    )

    assert dup.valid?, dup.errors.full_messages.join(", ")
  end
  # `end` closes this `test` block.

  test "full_address combines all address fields" do
    facility = facilities(:gilbert_public_storage)
    # `assert_equal expected, actual` fails unless the two values are
    # exactly (`==`) equal. `facility.full_address` (see
    # app/models/facility.rb) builds a single string interpolating address,
    # city, state, and zip, this checks the EXACT expected text, matching
    # the gilbert_public_storage fixture's stored values (see
    # test/fixtures/facilities.yml).
    assert_equal "670 S Gilbert Rd, Gilbert, AZ 85296", facility.full_address
  end
  # `end` closes this `test` block.

  test "geocodable_address strips suite/unit numbers" do
    facility = facilities(:gilbert_public_storage).dup
    # Overwrites the (in-memory only, unsaved) address with one that
    # includes a suite number, to test that geocodable_address (see
    # app/models/facility.rb) strips it out before geocoding, real
    # geocoding services often fail to match an address WITH a suite
    # number even though the base street address is fine.
    facility.address = "1015 S Val Vista Dr Ste 100"
    # Confirms "Ste 100" was removed, while city/state/zip (untouched by
    # this test) still come from the original fixture.
    assert_equal "1015 S Val Vista Dr, Gilbert, AZ 85296", facility.geocodable_address
  end
  # `end` closes this `test` block.

  test "distance_label formats distance or falls back to Unknown" do
    facility = facilities(:gilbert_public_storage)
    # The fixture has `distance_miles: 0.5` (see test/fixtures/facilities.yml)
    # , distance_label (see app/models/facility.rb) formats it to one
    # decimal place with a "miles" suffix.
    assert_equal "0.5 miles", facility.distance_label

    # Setting distance_miles to nil (in memory only, not saved) simulates a
    # facility with no distance data yet, distance_label should fall back
    # to the literal string "Unknown" rather than crash or print blank.
    facility.distance_miles = nil
    assert_equal "Unknown", facility.distance_label
  end
  # `end` closes this `test` block.

  test "formatted_phone formats a 10-digit number" do
    facility = facilities(:gilbert_public_storage)
    # The fixture's raw `phone:` value is "4805551234" (see
    # test/fixtures/facilities.yml), formatted_phone (see
    # app/models/facility.rb) strips it to digits-only then re-formats it
    # as a standard US phone number.
    assert_equal "(480) 555-1234", facility.formatted_phone
  end
  # `end` closes this `test` block.

  test "formatted_phone returns original string when it can't parse" do
    facility = facilities(:gilbert_public_storage).dup
    # Overwrites phone with a value that has no digits at all, after
    # stripping non-digit characters, formatted_phone gets a string of
    # length 0, which matches neither the 10-digit nor 11-digit branches in
    # app/models/facility.rb, so it should fall back to returning the
    # ORIGINAL (unparsed) string unchanged.
    facility.phone = "call the office"
    assert_equal "call the office", facility.formatted_phone
  end
  # `end` closes this `test` block.

  test "min_price returns the cheapest available unit's price" do
    facility = facilities(:gilbert_public_storage)
    # `units(:current_gilbert_10x10)` is a fixture lookup from
    # test/fixtures/units.yml, a Unit fixture that belongs to this same
    # facility (per its `facility: gilbert_public_storage` line in that
    # YAML file). `.monthly_price` reads that fixture's stored price.
    # `facility.min_price` (see app/models/facility.rb) queries this
    # facility's available units, sorted cheapest-first, and returns the
    # first one's price, this checks it matches the known-cheapest fixture.
    assert_equal units(:current_gilbert_10x10).monthly_price, facility.min_price
  end
  # `end` closes this `test` block.

  test "all_companies returns sorted distinct company names" do
    # `Facility.distinct.pluck(:company).sort` independently recomputes the
    # expected answer using plain ActiveRecord query methods, rather than
    # hardcoding a literal list of company names in this test, that way,
    # this test stays correct even if fixtures are added/changed later,
    # as long as `Facility.all_companies` (see app/models/facility.rb) is
    # actually doing the same distinct-and-sort logic itself.
    assert_equal Facility.distinct.pluck(:company).sort, Facility.all_companies
  end
  # `end` closes this `test` block.
end
# `end` closes the `class FacilityTest < ActiveSupport::TestCase` block that
# started at the top of this file.
