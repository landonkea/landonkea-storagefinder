# =============================================================================
# EXPORTS CONTROLLER
# =============================================================================
# Handles CSV and Excel downloads of the current results.
# Nothing auto-downloads — the user must click a button.
# =============================================================================

class ExportsController < ApplicationController
  # ---------------------------------------------------------------------------
  # CSV — download current results as a CSV file
  # ---------------------------------------------------------------------------
  def csv
    latest_crawl = CrawlRun.latest_completed

    unless latest_crawl
      flash[:alert] = "No crawl data to export. Run a crawl first."
      redirect_to root_path
      return
    end

    units = fetch_filtered_units(latest_crawl)

    # Generate a filename with the current date
    filename = "storagefinder_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv"

    # Build the CSV content
    csv_content = build_csv(units)

    # Send the file to the browser
    # send_data triggers a file download in the browser (not a page navigation)
    send_data csv_content,
              filename:    filename,
              type:        "text/csv; charset=utf-8",
              disposition: "attachment"  # "attachment" = download, not display

  rescue => e
    Rails.logger.error("[ExportsController] CSV export failed: #{e.class}: #{e.message}")
    flash[:alert] = "CSV export failed: #{e.message}"
    redirect_to root_path
  end

  # ---------------------------------------------------------------------------
  # EXCEL — download current results as a .xlsx Excel file
  # ---------------------------------------------------------------------------
  def excel
    latest_crawl = CrawlRun.latest_completed

    unless latest_crawl
      flash[:alert] = "No crawl data to export. Run a crawl first."
      redirect_to root_path
      return
    end

    @units   = fetch_filtered_units(latest_crawl)
    filename = "storagefinder_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx"

    # The dashboard's "Excel" link is a plain <a href> with no format
    # specifier, so the browser sends Accept: text/html — without forcing
    # the format here, respond_to's format.xlsx block never matches and
    # every request raises ActionController::UnknownFormat. This endpoint
    # only ever serves xlsx, regardless of what the browser asked for.
    request.format = :xlsx

    # The render call uses caxlsx_rails to process the Excel template
    # The template is at app/views/exports/excel.xlsx.axlsx
    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=#{filename}"
      }
    end

  rescue => e
    Rails.logger.error("[ExportsController] Excel export failed: #{e.class}: #{e.message}")
    flash[:alert] = "Excel export failed: #{e.message}"
    redirect_to root_path
  end

  # ---------------------------------------------------------------------------
  # PRIVATE
  # ---------------------------------------------------------------------------
  private

  # Fetch units from the latest crawl with the same filters the dashboard uses
  def fetch_filtered_units(crawl_run)
    crawl_run.units
             .includes(:facility)
             .where(climate_controlled: true)
             .where(drive_up: false, indoor: true)
             .where(available: true)
             .where.not(unit_type: Unit::EXCLUDED_TYPES)
             .where(size: Unit::DEFAULT_SIZES)
             .order(:monthly_price)
  end

  # Build CSV content from a collection of units
  def build_csv(units)
    require "csv"

    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      # Header row
      csv << [
        "Company",
        "Facility Name",
        "Address",
        "City",
        "State",
        "ZIP",
        "Phone",
        "Distance (miles)",
        "Unit Size",
        "Sq Ft",
        "Monthly Price",
        "Web Special Price",
        "Web Special Note",
        "Admin Fee",
        "Insurance",
        "Climate Controlled",
        "Available",
        "Booking URL",
        "Date Collected"
      ]

      # Data rows
      units.each do |unit|
        f = unit.facility  # Shorthand for facility
        csv << [
          f.company,
          f.name,
          f.address,
          f.city,
          f.state,
          f.zip,
          f.formatted_phone,
          f.distance_miles,
          unit.size,
          unit.sqft,
          unit.monthly_price,
          unit.web_special_price,
          unit.web_special_note,
          unit.admin_fee,
          unit.insurance_note,
          unit.climate_controlled? ? "Yes" : "No",
          unit.available? ? "Yes" : "No",
          unit.booking_url,
          unit.collected_at&.strftime("%Y-%m-%d %H:%M:%S")
        ]
      end
    end
  end
end
