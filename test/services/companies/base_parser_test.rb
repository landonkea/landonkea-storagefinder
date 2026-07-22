require "test_helper"

# BaseParser is abstract (company_name/company_slug/etc. raise
# NotImplementedError) and its browser-facing methods (open_page,
# take_error_screenshot, parse_locations, parse_units) need a real
# Playwright page — not something to fake convincingly in a unit test. This
# covers the pure, browser-independent shared logic every company parser
# inherits: price/size parsing, filtering, and the Facility upsert logic.
class TestParser < Companies::BaseParser
  def company_name = "Test Co"
  def company_slug = "test_co"
  def search_url(lat, lng, radius_miles) = "https://example.com/search"
  def parse_locations(page) = []
  def parse_units(page, facility) = []
end

class BaseParserTest < ActiveSupport::TestCase
  def parser(options: {})
    TestParser.new(crawl_run: crawl_runs(:current_completed), browser: Object.new, options: options)
  end

  test "parse_price extracts a decimal from various formats" do
    p = parser
    assert_equal 89.0, p.send(:parse_price, "$89.00/mo")
    assert_equal 89.0, p.send(:parse_price, "89")
    assert_equal 1234.5, p.send(:parse_price, "$1,234.50")
  end

  test "parse_price returns nil for blank or zero prices" do
    p = parser
    assert_nil p.send(:parse_price, nil)
    assert_nil p.send(:parse_price, "")
    assert_nil p.send(:parse_price, "$0")
    assert_nil p.send(:parse_price, "call for pricing")
  end

  test "parse_size normalizes various size formats to WIDTHxDEPTH" do
    p = parser
    assert_equal "10x20", p.send(:parse_size, "10x20")
    assert_equal "10x20", p.send(:parse_size, "10' x 20'")
    assert_equal "10x20", p.send(:parse_size, "10 X 20 ft")
  end

  test "parse_size returns nil when it can't find two numbers" do
    p = parser
    assert_nil p.send(:parse_size, nil)
    assert_nil p.send(:parse_size, "")
    assert_nil p.send(:parse_size, "large")
  end

  test "apply_filters drops units smaller than the 10x10 minimum" do
    p = parser
    units = [ { size: "5x5", unit_type: "standard", climate_controlled: true } ]
    assert_empty p.send(:apply_filters, units)
  end

  test "apply_filters drops excluded unit types" do
    p = parser
    units = [ { size: "10x10", unit_type: "parking", climate_controlled: true } ]
    assert_empty p.send(:apply_filters, units)
  end

  test "apply_filters requires climate control only when that option is set" do
    p = parser(options: { climate_controlled: true })
    units = [ { size: "10x10", unit_type: "standard", climate_controlled: false } ]
    assert_empty p.send(:apply_filters, units)
  end

  test "apply_filters buckets non-standard sizes into the closest selected size" do
    p = parser(options: { sizes: [ "10x10" ] })
    # 10x12 (120 sqft) is closer to 10x10 (100 sqft) than 10x15 (150 sqft)
    units = [ { size: "10x12", unit_type: "standard", climate_controlled: false } ]
    result = p.send(:apply_filters, units)
    assert_equal 1, result.length
  end

  test "apply_filters keeps drive-up/outdoor units (no UI control excludes them here)" do
    p = parser
    units = [ { size: "10x10", unit_type: "standard", climate_controlled: false, drive_up: true } ]
    assert_equal 1, p.send(:apply_filters, units).length
  end

  test "upsert_facility matching is scoped to the parser's own company" do
    p = parser
    existing = facilities(:gilbert_public_storage) # company: "Public Storage"

    found = p.send(:upsert_facility, {
      name: "Renamed", address: existing.address, city: existing.city,
      state: existing.state, zip: existing.zip, external_id: existing.external_id
    })

    # upsert_facility scopes by the parser's own company_name ("Test Co"),
    # so a matching external_id under a DIFFERENT company creates a new
    # record rather than reusing (and silently renaming) the other one.
    assert_equal "Test Co", found.company
    refute_equal existing.id, found.id
  end

  test "upsert_facility updates an existing record on a second call with the same external_id" do
    p = parser
    location_data = {
      name: "First Name", address: "1 Test St", city: "Testville", state: "AZ",
      zip: "85000", external_id: "unique-123"
    }

    first  = p.send(:upsert_facility, location_data)
    second = p.send(:upsert_facility, location_data.merge(name: "Updated Name"))

    assert_equal first.id, second.id
    assert_equal "Updated Name", second.reload.name
  end

  test "upsert_facility raises with a clear message when the facility is invalid" do
    p = parser
    error = assert_raises(RuntimeError) do
      p.send(:upsert_facility, { name: "No address", city: "Testville", state: "AZ", zip: "85000" })
    end
    assert_match(/Could not save facility/, error.message)
  end

  test "save_unit persists a unit associated with the facility and crawl run" do
    p = parser
    facility = facilities(:gilbert_public_storage)

    unit = p.send(:save_unit, { size: "10x10", monthly_price: 100, collected_at: Time.current }, facility)

    assert unit.persisted?
    assert_equal facility, unit.facility
    assert_equal crawl_runs(:current_completed), unit.crawl_run
  end
end
