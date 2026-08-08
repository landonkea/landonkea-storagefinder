require "test_helper"

module Api
  module V1
    class FacilitiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @api_key = ApiKey.create!(name: "Test key")
      end

      def auth_headers(token = @api_key.token)
        { "HTTP_AUTHORIZATION" => "Bearer #{token}" }
      end

      test "rejects requests with no api key" do
        get api_v1_facilities_path, headers: { "HTTP_AUTHORIZATION" => nil }
        assert_response :unauthorized
      end

      test "rejects requests with an invalid api key" do
        get api_v1_facilities_path, headers: auth_headers("not-a-real-token")
        assert_response :unauthorized
      end

      test "rejects requests with a revoked (inactive) api key" do
        @api_key.update!(active: false)
        get api_v1_facilities_path, headers: auth_headers
        assert_response :unauthorized
      end

      test "returns facilities as json with a valid api key" do
        get api_v1_facilities_path, headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["facilities"].is_a?(Array)
        assert body["facilities"].size >= 2
        assert body["meta"]["total"] >= 2

        facility = body["facilities"].find { |f| f["name"] == facilities(:gilbert_public_storage).name }
        assert facility.present?
        assert_equal "Public Storage", facility["company"]
      end

      test "accepts the api key via api_key query param" do
        get api_v1_facilities_path(api_key: @api_key.token), headers: { "HTTP_AUTHORIZATION" => nil }
        assert_response :success
      end

      test "filters by company" do
        get api_v1_facilities_path(company: "Public Storage"), headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["facilities"].all? { |f| f["company"] == "Public Storage" }
      end

      test "includes distance_miles when lat/lng are given" do
        get api_v1_facilities_path(lat: 33.3528, lng: -111.7890), headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["facilities"].all? { |f| f.key?("distance_miles") }
      end

      test "records usage on the api key" do
        assert_equal 0, @api_key.request_count

        get api_v1_facilities_path, headers: auth_headers

        assert_equal 1, @api_key.reload.request_count
        assert @api_key.last_used_at.present?
      end

      test "show returns a single facility with its units" do
        facility = facilities(:gilbert_public_storage)
        get api_v1_facility_path(facility), headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert_equal facility.id, body["id"]
        assert body["units"].is_a?(Array)
      end

      test "show returns 404 json for an unknown facility" do
        get api_v1_facility_path(id: 999_999), headers: auth_headers
        assert_response :not_found

        body = JSON.parse(response.body)
        assert_equal "Not found", body["error"]
      end
    end
  end
end
