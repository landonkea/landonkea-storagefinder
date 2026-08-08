require "test_helper"

module Api
  module V1
    class UnitsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @api_key = ApiKey.create!(name: "Test key")
      end

      def auth_headers
        { "HTTP_AUTHORIZATION" => "Bearer #{@api_key.token}" }
      end

      test "rejects requests with no api key" do
        get api_v1_units_path, headers: { "HTTP_AUTHORIZATION" => nil }
        assert_response :unauthorized
      end

      test "returns available units by default" do
        get api_v1_units_path, headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["units"].is_a?(Array)
        assert body["units"].all? { |u| u["available"] }
      end

      test "filters by facility_id" do
        facility = facilities(:gilbert_public_storage)
        get api_v1_units_path(facility_id: facility.id), headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["units"].all? { |u| u["facility"]["id"] == facility.id }
      end

      test "filters by max_price" do
        get api_v1_units_path(max_price: 100), headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["units"].all? { |u| u["monthly_price"].to_f <= 100 }
      end

      test "includes facility summary on each unit" do
        get api_v1_units_path, headers: auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        unit = body["units"].first
        assert unit["facility"]["company"].present?
      end
    end
  end
end
