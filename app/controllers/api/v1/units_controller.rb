# =============================================================================
# API::V1::UNITS CONTROLLER
# =============================================================================
# Read-only JSON endpoint for unit-level pricing/availability data,
# authenticated via ApiKey. Reuses Unit.apply_filters (the same filtering
# logic the dashboard uses) so API consumers get identical semantics to the
# dashboard's filter checkboxes rather than a second, drifting copy of the
# rules.
# =============================================================================

module Api
  module V1
    class UnitsController < Api::BaseController
      # GET /api/v1/units
      # Optional query params:
      #   facility_id         — restrict to one facility
      #   climate_controlled  — "true"/"false"
      #   available_only      — "true" to exclude unavailable units (default: true)
      #   include_unavailable — "true" to include unavailable units
      #   sizes[]             — array of size strings, e.g. sizes[]=10x10
      #   max_price           — only units at or below this monthly price
      #   limit / offset      — pagination, same rules as FacilitiesController
      def index
        scope = Unit.apply_filters(filter_options).includes(:facility)
        scope = scope.where(facility_id: params[:facility_id]) if params[:facility_id].present?
        scope = scope.where(monthly_price: ..parsed_max_price) if params[:max_price].present?

        total = scope.count
        units = scope.order(:monthly_price).limit(page_limit).offset(page_offset)

        render json: {
          units: units.map { |unit| unit_json(unit) },
          meta: { total: total, limit: page_limit, offset: page_offset }
        }
      end

      private

      def filter_options
        {
          climate_controlled: params[:climate_controlled],
          sizes: Array(params[:sizes]).presence,
          include_unavailable: ActiveModel::Type::Boolean.new.cast(params[:include_unavailable])
        }
      end

      def parsed_max_price
        price = Float(params[:max_price], exception: false)
        raise Api::BaseController::InvalidParameter, "max_price must be numeric." if price.nil?

        price
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
          collected_at: unit.collected_at&.iso8601,
          facility: {
            id: unit.facility.id,
            company: unit.facility.company,
            name: unit.facility.name,
            city: unit.facility.city,
            state: unit.facility.state
          }
        }
      end
    end
  end
end
