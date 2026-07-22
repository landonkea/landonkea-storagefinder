# =============================================================================
# DASHBOARD CONTROLLER
# =============================================================================
# Handles the main dashboard page where users:
#   - See current storage unit results
#   - Set filter options
#   - Run crawls
#   - View price history graphs
# =============================================================================

class DashboardController < ApplicationController
  # ---------------------------------------------------------------------------
  # INDEX — the main dashboard page
  # ---------------------------------------------------------------------------
  def index
    @page_title = "Dashboard — StorageFinder"

    # -------------------------------------------------------------------------
    # Load the most recent crawl run (if any)
    # -------------------------------------------------------------------------
    @latest_crawl = CrawlRun.latest_completed

    # Is a crawl currently running?
    @crawl_running = CrawlRun.any_running?
    @running_crawl = CrawlRun.running.first

    # -------------------------------------------------------------------------
    # Build the results query from the latest crawl
    # -------------------------------------------------------------------------
    if @latest_crawl
      @units = build_results_query(@latest_crawl)
    else
      @units = Unit.none  # Empty — no crawl has been run yet
    end

    # -------------------------------------------------------------------------
    # Filter options for the UI
    # -------------------------------------------------------------------------
    @available_companies = CompanyRegistry.all_company_names
    @available_sizes     = Unit::DEFAULT_SIZES
    @all_sizes_in_db     = Unit.all_sizes  # Sizes actually found in the database

    # Selected filters (from the URL params, or defaults)
    @selected_sizes      = params[:sizes]&.split(",") || Unit::DEFAULT_SIZES
    @climate_only        = params[:climate_only] != "false"   # Default: true
    @selected_companies  = params[:companies]&.split(",") || @available_companies
    @sort_by             = params[:sort] || "monthly_price"
    @sort_dir            = params[:dir] || "asc"

    # -------------------------------------------------------------------------
    # Price history data for the trend chart
    # -------------------------------------------------------------------------
    @price_history = build_price_history

    # -------------------------------------------------------------------------
    # Crawl history for the history panel
    # -------------------------------------------------------------------------
    history_months = Setting.get("history_keep_months", default: 6).to_i
    @crawl_history  = CrawlRun.history(months: history_months).limit(20)
  end

  # ---------------------------------------------------------------------------
  # STATUS — JSON endpoint for live crawl status polling
  # The JavaScript on the dashboard calls this to check if a crawl is still running
  # ---------------------------------------------------------------------------
  def status
    running = CrawlRun.any_running?
    latest  = CrawlRun.latest_completed

    render json: {
      crawl_running:    running,
      running_crawl_id: CrawlRun.running.first&.id,
      latest_crawl: {
        id:               latest&.id,
        status:           latest&.status,
        facilities_found: latest&.facilities_found,
        units_found:      latest&.units_found,
        completed_at:     latest&.completed_at&.iso8601
      }
    }
  end

  # ---------------------------------------------------------------------------
  # RESULTS — JSON endpoint that returns the filtered unit results table
  # Called via AJAX when filters change or a crawl finishes
  # ---------------------------------------------------------------------------
  def results
    latest_crawl = CrawlRun.latest_completed

    unless latest_crawl
      render json: { units: [], message: "No crawl data yet. Run a crawl to see results." }
      return
    end

    units = build_results_query(latest_crawl)

    # Build a simple array of unit data for the JSON response
    unit_data = units.includes(:facility).map do |unit|
      {
        id:                 unit.id,
        company:            unit.facility.company,
        facility_name:      unit.facility.name,
        address:            unit.facility.full_address,
        city:               unit.facility.city,
        distance_miles:     unit.facility.distance_miles,
        phone:              unit.facility.formatted_phone,
        size:               unit.size,
        sqft:               unit.sqft,
        monthly_price:      unit.monthly_price,
        web_special_price:  unit.web_special_price,
        web_special_note:   unit.web_special_note,
        best_price:         unit.best_price,
        price_color:        unit.price_color_class,
        climate_controlled: unit.climate_controlled?,
        available:          unit.available?,
        booking_url:        unit.booking_url,
        maps_url:           unit.facility.maps_url,
        collected_at:       unit.collected_at&.strftime("%b %d at %I:%M %p")
      }
    end

    render json: { units: unit_data, total: unit_data.length }
  end

  # ---------------------------------------------------------------------------
  # PRIVATE HELPERS
  # ---------------------------------------------------------------------------
  private

  # Builds the ActiveRecord query for results based on current filter params
  def build_results_query(crawl_run)
    query = crawl_run.units.includes(:facility)

    # Apply climate controlled filter
    if params[:climate_only] != "false"
      query = query.where(climate_controlled: true)
    end

    # Apply size filter
    if params[:sizes].present?
      selected_sizes = params[:sizes].split(",")
      query = query.where(size: selected_sizes)
    else
      query = query.where(size: Unit::DEFAULT_SIZES)
    end

    # Apply company filter
    if params[:companies].present?
      selected_companies = params[:companies].split(",")
      query = query.joins(:facility).where(facilities: { company: selected_companies })
    end

    # Exclude non-standard unit types
    query = query.where.not(unit_type: Unit::EXCLUDED_TYPES)

    # Only indoor, non-drive-up units
    query = query.where(drive_up: false, indoor: true)

    # Only available units (can be toggled off via params)
    query = query.where(available: true) unless params[:include_unavailable] == "true"

    # Apply sorting
    sort_column = sanitize_sort_column(params[:sort] || "monthly_price")
    sort_dir    = params[:dir] == "desc" ? "desc" : "asc"

    query.order("#{sort_column} #{sort_dir}")
  end

  # Prevent SQL injection in sort column by whitelisting allowed columns
  def sanitize_sort_column(column)
    allowed = %w[monthly_price sqft facilities.distance_miles facilities.company size]
    allowed.include?(column) ? column : "monthly_price"
  end

  # Build price history data for the trend chart
  # Returns data grouped by week for the last 6 months
  def build_price_history
    months_back = Setting.get("history_keep_months", default: 6).to_i

    Unit.where("collected_at >= ?", months_back.months.ago)
        .where(size: Unit::DEFAULT_SIZES)
        .where(climate_controlled: true)
        .where.not(monthly_price: nil)
        .group_by_week(:collected_at)
        .average(:monthly_price)
  rescue => e
    Rails.logger.warn("[DashboardController] Could not build price history: #{e.message}")
    {}
  end
end
