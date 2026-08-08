# =============================================================================
# API::V1::FACILITIES CONTROLLER
# =============================================================================
# Read-only JSON endpoints for facility data, authenticated via ApiKey (see
# app/controllers/api/base_controller.rb). Mirrors the filtering already
# available to the dashboard (company, city, nearest-to-a-point) but exposes
# it over HTTP for external tools/scripts rather than the browser dashboard.
# =============================================================================

module Api
  module V1
    class FacilitiesController < Api::BaseController
      # GET /api/v1/facilities
      # Optional query params:
      #   company       — exact company name match, e.g. "Public Storage"
      #   city          — exact city match, e.g. "Gilbert"
      #   lat / lng     — sorts results by distance from this point (miles)
      #                   and includes a computed "distance_miles" per facility
      #   limit         — page size, default 50, capped at 100
      #   offset        — pagination offset, default 0
      def index
        scope = Facility.all
        scope = scope.for_company(params[:company]) if params[:company].present?
        scope = scope.in_city(params[:city]) if params[:city].present?

        origin = origin_coordinates
        scope = scope.nearest_to(origin[:lat], origin[:lng]) if origin

        total = scope.count
        facilities = scope.limit(page_limit).offset(page_offset).includes(:units)

        render json: {
          facilities: facilities.map { |facility| facility_json(facility, origin) },
          meta: { total: total, limit: page_limit, offset: page_offset }
        }
      end

      # GET /api/v1/facilities/:id
      def show
        facility = Facility.includes(:units).find(params[:id])
        render json: facility_json(facility, origin_coordinates, include_units: true)
      end

      private

      def origin_coordinates
        return nil if params[:lat].blank? || params[:lng].blank?

        { lat: params[:lat].to_f, lng: params[:lng].to_f }
      end

      def page_limit
        [ params.fetch(:limit, 50).to_i, 100 ].min.clamp(1, 100)
      end

      def page_offset
        [ params.fetch(:offset, 0).to_i, 0 ].max
      end

      def facility_json(facility, origin, include_units: false)
        json = {
          id: facility.id,
          company: facility.company,
          name: facility.name,
          address: facility.address,
          city: facility.city,
          state: facility.state,
          zip: facility.zip,
          phone: facility.formatted_phone,
          latitude: facility.latitude,
          longitude: facility.longitude,
          min_price: facility.min_price,
          available_unit_count: facility.available_unit_count,
          climate_controlled: facility.has_climate_control?,
          maps_url: facility.maps_url
        }

        if origin && facility.latitude && facility.longitude
          json[:distance_miles] = Geocoder::Calculations.distance_between(
            [ origin[:lat], origin[:lng] ],
            [ facility.latitude, facility.longitude ],
            units: :mi
          ).round(1)
        end

        json[:units] = facility.units.map { |unit| unit_json(unit) } if include_units

        json
      end

      def unit_json(unit)
        {
          id: unit.id,
          size: unit.size,
          sqft: unit.sqft,
          monthly_price: unit.monthly_price,
          best_price: unit.best_price,
          available: unit.available,
          climate_controlled: unit.climate_controlled,
          indoor: unit.indoor,
          drive_up: unit.drive_up,
          unit_type: unit.unit_type,
          collected_at: unit.collected_at&.iso8601
        }
      end
    end
  end
end
