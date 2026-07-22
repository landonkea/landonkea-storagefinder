require "test_helper"

class UnitTest < ActiveSupport::TestCase
  def valid_attributes
    {
      facility: facilities(:gilbert_public_storage),
      crawl_run: crawl_runs(:current_completed),
      size: "10x10",
      monthly_price: 100,
      collected_at: Time.current
    }
  end

  test "requires size and collected_at" do
    unit = Unit.new
    refute unit.valid?
    assert_includes unit.errors[:size], "Unit size is required (e.g. 10x10)"
    assert_includes unit.errors[:collected_at], "Collection timestamp is required"
  end

  test "size must match WIDTHxDEPTH format" do
    unit = Unit.new(valid_attributes.merge(size: "not-a-size"))
    refute unit.valid?
    assert_includes unit.errors[:size], "Size must be in WIDTHxDEPTH format (e.g. 10x10, 10x20)"
  end

  test "monthly_price must be greater than 0 when present" do
    unit = Unit.new(valid_attributes.merge(monthly_price: 0))
    refute unit.valid?
    assert_includes unit.errors[:monthly_price], "Monthly price must be greater than $0"
  end

  test "monthly_price may be nil" do
    unit = Unit.new(valid_attributes.merge(monthly_price: nil))
    assert unit.valid?, unit.errors.full_messages.join(", ")
  end

  test "parses width/depth/sqft from size before saving" do
    unit = Unit.create!(valid_attributes.merge(size: "10x20"))
    assert_equal 10, unit.width_ft
    assert_equal 20, unit.depth_ft
    assert_equal 200, unit.sqft
  end

  test "best_price prefers the web special when it's cheaper" do
    unit = Unit.new(monthly_price: 150, web_special_price: 99)
    assert_equal 99, unit.best_price
  end

  test "best_price falls back to monthly_price when there's no cheaper special" do
    unit = Unit.new(monthly_price: 150, web_special_price: 175)
    assert_equal 150, unit.best_price
  end

  test "best_price handles a nil monthly_price" do
    unit = Unit.new(monthly_price: nil, web_special_price: 99)
    assert_equal 99, unit.best_price

    unit2 = Unit.new(monthly_price: nil, web_special_price: nil)
    assert_nil unit2.best_price
  end

  test "has_web_special? is true only when the special is cheaper" do
    assert Unit.new(monthly_price: 150, web_special_price: 99).has_web_special?
    refute Unit.new(monthly_price: 150, web_special_price: 175).has_web_special?
    refute Unit.new(monthly_price: 150, web_special_price: nil).has_web_special?
  end

  test "formatted_price handles nil" do
    assert_equal "Not listed", Unit.new(monthly_price: nil).formatted_price
    assert_equal "$89.00", Unit.new(monthly_price: 89).formatted_price
  end

  test "price_color_class buckets by best_price" do
    assert_equal "price-unknown", Unit.new(monthly_price: nil).price_color_class
    assert_equal "price-green",   Unit.new(monthly_price: 50).price_color_class
    assert_equal "price-yellow",  Unit.new(monthly_price: 120).price_color_class
    assert_equal "price-red",     Unit.new(monthly_price: 200).price_color_class
  end

  test "matches_default_filters? requires climate control, indoor, non-drive-up, and minimum size" do
    good = Unit.new(
      climate_controlled: true, indoor: true, drive_up: false,
      unit_type: "standard", width_ft: 10, depth_ft: 10
    )
    assert good.matches_default_filters?

    too_small = good.dup
    too_small.width_ft = 5
    refute too_small.matches_default_filters?

    excluded_type = good.dup
    excluded_type.unit_type = "parking"
    refute excluded_type.matches_default_filters?
  end

  test "apply_filters scopes by climate control, size, and defaults to available/indoor/non-drive-up" do
    results = Unit.apply_filters(sizes: [ "10x10" ])
    assert_includes results, units(:current_gilbert_10x10)
    refute_includes results, units(:current_mesa_10x15)
  end

  test "all_sizes returns sizes sorted by square footage" do
    sizes = Unit.all_sizes
    assert_equal sizes.sort_by { |s| s.split("x").map(&:to_i).reduce(:*) }, sizes
  end
end
