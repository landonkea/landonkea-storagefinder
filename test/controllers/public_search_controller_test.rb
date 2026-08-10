# `require "test_helper"` loads the shared test setup, including the
# global HTTP Basic Auth header injection described in test_helper.rb, and
# the fixtures loaded from test/fixtures/*.yml (facilities.yml, units.yml).
require "test_helper"

# Exercises PublicSearchController: the customer-facing search/comparison
# page that must be reachable WITHOUT credentials (unlike every other
# controller in this app, which test_helper.rb auto-authenticates). Every
# test below that wants to prove "no auth needed" does so explicitly by
# overriding the auto-injected header with `headers: { "HTTP_AUTHORIZATION" => nil }`
#, the same pattern test/controllers/authentication_test.rb uses to prove
# the OPPOSITE (that the admin gate rejects unauthenticated requests).
class PublicSearchControllerTest < ActionDispatch::IntegrationTest
  # ---------------------------------------------------------------------------
  # SECURITY: reachable without credentials
  # ---------------------------------------------------------------------------
  test "index is reachable without any credentials" do
    get public_search_path, headers: { "HTTP_AUTHORIZATION" => nil }
    assert_response :success
    assert_select "title", /StorageFinder/
  end

  test "index rejects nothing, even explicitly WRONG credentials still succeed (no auth gate at all)" do
    # Proves this isn't merely tolerant of a missing header, it truly
    # doesn't check credentials at all, unlike ApplicationController's gate.
    get public_search_path, headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong")
    }
    assert_response :success
  end

  test "facility detail page is reachable without any credentials" do
    get public_search_facility_path(facilities(:gilbert_public_storage)), headers: { "HTTP_AUTHORIZATION" => nil }
    assert_response :success
  end

  test "public pages do not link to the admin dashboard, alert rules, or settings" do
    get public_search_path, headers: { "HTTP_AUTHORIZATION" => nil }
    assert_response :success
    # The admin nav (layouts/application.html.erb) links to these by exact
    # text, confirming they're absent here proves the public layout really
    # is a separate template, not just the admin layout re-themed.
    assert_no_match "Alert Rules", response.body
    assert_no_match "Settings", response.body
  end

  # ---------------------------------------------------------------------------
  # SEARCH RESULTS
  # ---------------------------------------------------------------------------
  test "index lists facilities that have at least one available unit" do
    get public_search_path
    assert_response :success
    assert_match facilities(:gilbert_public_storage).name, response.body
    assert_match facilities(:mesa_extra_space).name, response.body
  end

  test "index excludes facilities with no available units at all" do
    # no_external_id_facility has no Unit fixtures pointing at it, it
    # should never appear in default (unfiltered) results.
    get public_search_path
    assert_response :success
    assert_no_match facilities(:no_external_id_facility).name, response.body
  end

  test "index filters by city" do
    get public_search_path, params: { city: "Gilbert" }
    assert_response :success
    assert_match facilities(:gilbert_public_storage).name, response.body
    assert_no_match facilities(:mesa_extra_space).name, response.body
  end

  test "index filters by unit size" do
    # Only mesa_extra_space has any 10x15 units (see test/fixtures/units.yml)
    #, gilbert_public_storage only has 10x10s.
    get public_search_path, params: { sizes: [ "10x15" ] }
    assert_response :success
    assert_match facilities(:mesa_extra_space).name, response.body
    assert_no_match facilities(:gilbert_public_storage).name, response.body
  end

  test "index filters by price range" do
    # current_gilbert_10x10 is $120 (available). Everything else available
    # is either $90 (mesa) or $150/$200 (the "previous" crawl prices),
    # a 100..130 range should isolate just the gilbert facility.
    get public_search_path, params: { min_price: 100, max_price: 130 }
    assert_response :success
    assert_match facilities(:gilbert_public_storage).name, response.body
    assert_no_match facilities(:mesa_extra_space).name, response.body
  end

  test "index sorts by price ascending by default" do
    get public_search_path
    assert_response :success
    mesa_position    = response.body.index(facilities(:mesa_extra_space).name)     # $90, cheapest
    gilbert_position = response.body.index(facilities(:gilbert_public_storage).name) # $120
    assert mesa_position < gilbert_position, "expected the cheaper facility (mesa, $90) to be listed before the pricier one (gilbert, $120)"
  end

  test "index sorts by price descending when requested" do
    get public_search_path, params: { sort: "price", dir: "desc" }
    assert_response :success
    mesa_position    = response.body.index(facilities(:mesa_extra_space).name)
    gilbert_position = response.body.index(facilities(:gilbert_public_storage).name)
    assert gilbert_position < mesa_position, "expected the pricier facility (gilbert, $120) to be listed before the cheaper one (mesa, $90) in desc order"
  end

  test "index sorts by distance when an origin point is given" do
    # Origin coordinates match gilbert_public_storage's own location almost
    # exactly (see test/fixtures/facilities.yml), much closer than
    # mesa_extra_space, so gilbert should sort first.
    get public_search_path, params: { sort: "distance", lat: 33.3528, lng: -111.7890 }
    assert_response :success
    gilbert_position = response.body.index(facilities(:gilbert_public_storage).name)
    mesa_position    = response.body.index(facilities(:mesa_extra_space).name)
    assert gilbert_position < mesa_position, "expected the closer facility (gilbert) to be listed before the farther one (mesa)"
  end

  test "index falls back to price sorting when distance is requested without an origin" do
    get public_search_path, params: { sort: "distance" }
    assert_response :success
    assert_select "title", /StorageFinder/
  end

  test "index shows an empty state instead of erroring when nothing matches" do
    get public_search_path, params: { min_price: 9999 }
    assert_response :success
    assert_match "No facilities match your search", response.body
  end

  # ---------------------------------------------------------------------------
  # FACILITY DETAIL
  # ---------------------------------------------------------------------------
  test "show displays current unit pricing and availability" do
    get public_search_facility_path(facilities(:gilbert_public_storage))
    assert_response :success
    assert_match facilities(:gilbert_public_storage).name, response.body
    # current_gilbert_10x10's price ($120.00) should be shown.
    assert_match "$120.00", response.body
  end

  test "show only lists available units" do
    facility = facilities(:gilbert_public_storage)
    unavailable_unit = units(:current_gilbert_10x10)
    unavailable_unit.update!(available: false, monthly_price: 999.99)

    get public_search_facility_path(facility)
    assert_response :success
    assert_no_match "$999.99", response.body
  end

  test "show redirects with a flash message for an unknown facility id" do
    get public_search_facility_path(id: 999_999)
    assert_redirected_to public_search_path
    follow_redirect!
    assert_match "couldn&#39;t be found", response.body
  end
end
