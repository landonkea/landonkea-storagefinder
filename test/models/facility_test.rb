require "test_helper"

class FacilityTest < ActiveSupport::TestCase
  test "requires company, name, address, city, state, zip" do
    facility = Facility.new
    refute facility.valid?
    %i[company name address city state zip].each do |attr|
      assert_includes facility.errors.attribute_names, attr
    end
  end

  test "zip must be 5 digits or ZIP+4" do
    facility = facilities(:gilbert_public_storage).dup
    facility.external_id = "unique-zip-test"

    facility.zip = "85296"
    assert facility.valid?

    facility.zip = "85296-1234"
    assert facility.valid?

    facility.zip = "abc"
    refute facility.valid?
    assert_includes facility.errors[:zip], "ZIP must be 5 digits or ZIP+4 format (e.g. 85296)"
  end

  test "external_id must be unique per company" do
    existing = facilities(:gilbert_public_storage)
    dup = Facility.new(
      company: existing.company, name: "Dup", address: "999 Other Rd",
      city: "Gilbert", state: "AZ", zip: "85296", external_id: existing.external_id
    )

    refute dup.valid?
    assert_includes dup.errors[:external_id], "already has a facility with this external ID for this company"
  end

  test "the same external_id is fine for a different company" do
    existing = facilities(:gilbert_public_storage)
    other = Facility.new(
      company: "A Totally Different Company", name: "Other", address: "1 Other Rd",
      city: "Gilbert", state: "AZ", zip: "85296", external_id: existing.external_id
    )

    assert other.valid?, other.errors.full_messages.join(", ")
  end

  test "address must be unique per company+city+state when external_id is blank" do
    existing = facilities(:no_external_id_facility)
    dup = Facility.new(
      company: existing.company, name: "Dup", address: existing.address,
      city: existing.city, state: existing.state, zip: "85286"
    )

    refute dup.valid?
    assert_includes dup.errors[:address], "already has a facility at this address for this company"
  end

  test "duplicate address is fine when external_id is present" do
    existing = facilities(:no_external_id_facility)
    dup = Facility.new(
      company: existing.company, name: "Dup", address: existing.address,
      city: existing.city, state: existing.state, zip: "85286", external_id: "some-id"
    )

    assert dup.valid?, dup.errors.full_messages.join(", ")
  end

  test "full_address combines all address fields" do
    facility = facilities(:gilbert_public_storage)
    assert_equal "670 S Gilbert Rd, Gilbert, AZ 85296", facility.full_address
  end

  test "geocodable_address strips suite/unit numbers" do
    facility = facilities(:gilbert_public_storage).dup
    facility.address = "1015 S Val Vista Dr Ste 100"
    assert_equal "1015 S Val Vista Dr, Gilbert, AZ 85296", facility.geocodable_address
  end

  test "distance_label formats distance or falls back to Unknown" do
    facility = facilities(:gilbert_public_storage)
    assert_equal "0.5 miles", facility.distance_label

    facility.distance_miles = nil
    assert_equal "Unknown", facility.distance_label
  end

  test "formatted_phone formats a 10-digit number" do
    facility = facilities(:gilbert_public_storage)
    assert_equal "(480) 555-1234", facility.formatted_phone
  end

  test "formatted_phone returns original string when it can't parse" do
    facility = facilities(:gilbert_public_storage).dup
    facility.phone = "call the office"
    assert_equal "call the office", facility.formatted_phone
  end

  test "min_price returns the cheapest available unit's price" do
    facility = facilities(:gilbert_public_storage)
    assert_equal units(:current_gilbert_10x10).monthly_price, facility.min_price
  end

  test "all_companies returns sorted distinct company names" do
    assert_equal Facility.distinct.pluck(:company).sort, Facility.all_companies
  end
end
