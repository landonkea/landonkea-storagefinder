# =============================================================================
# EXPORTS CONTROLLER
# =============================================================================
# Handles CSV and Excel downloads of the current results.
# Nothing auto-downloads — the user must click a button.
# =============================================================================

# `class ExportsController < ApplicationController` — see
# app/controllers/application_controller.rb for what "controller" and
# "inherits from" mean.
class ExportsController < ApplicationController
  # ---------------------------------------------------------------------------
  # CSV — download current results as a CSV file
  # ---------------------------------------------------------------------------
  # `csv` is a custom action (needs an explicit route) triggered when the
  # user clicks a "Download CSV" link/button (GET /exports/csv or similar).
  # CSV = "Comma-Separated Values" — a plain-text spreadsheet format that
  # opens directly in Excel/Google Sheets.
  def csv
    latest_crawl = CrawlRun.latest_completed

    # If no crawl has ever finished, there's nothing to export.
    unless latest_crawl
      flash[:alert] = "No crawl data to export. Run a crawl first."
      redirect_to root_path
      return
    end
    # `end` closes the `unless latest_crawl` block above.

    # Delegates to the private `fetch_filtered_units` method below, which
    # applies the same result filters the dashboard uses.
    units = fetch_filtered_units(latest_crawl)

    # Generate a filename with the current date
    # `Time.current` is Rails' timezone-aware "now" (see
    # CrawlsController#destroy for the same note on why it's preferred over
    # plain Ruby `Time.now`). `.strftime("%Y%m%d_%H%M%S")` formats it as a
    # compact numeric timestamp (e.g. "20260718_143000") suitable for use
    # inside a filename, where spaces/colons/slashes would cause problems.
    filename = "storagefinder_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv"

    # Build the CSV content
    # Delegates to the private `build_csv` method below, which converts the
    # `units` ActiveRecord results into an actual CSV-formatted string.
    csv_content = build_csv(units)

    # Send the file to the browser
    # send_data triggers a file download in the browser (not a page navigation)
    # `send_data` is a Rails controller method that streams raw content
    # (here, the CSV text) straight to the browser as a file response,
    # rather than rendering an HTML page. Its keyword arguments configure
    # the download: `filename:` names the downloaded file; `type:` sets the
    # HTTP Content-Type header (telling the browser/OS what kind of file
    # this is); `disposition: "attachment"` tells the browser to prompt a
    # "Save As" download rather than trying to display the content inline
    # in the browser tab.
    send_data csv_content,
              filename:    filename,
              type:        "text/csv; charset=utf-8",
              disposition: "attachment"  # "attachment" = download, not display

  # `rescue => e` (bare rescue, catches StandardError and subclasses — see
  # DashboardController#build_price_history for the same pattern) applies
  # to the whole method body above, since exporting shouldn't hard-crash
  # the app if something in the CSV-building process goes wrong.
  rescue => e
    # `e.class` gives the specific error class (e.g. NoMethodError), logged
    # alongside `e.message` for easier debugging from server logs.
    Rails.logger.error("[ExportsController] CSV export failed: #{e.class}: #{e.message}")
    flash[:alert] = "CSV export failed: #{e.message}"
    redirect_to root_path
  end
  # `end` closes the `def csv` action definition (the `rescue` clause above
  # is part of this same method).

  # ---------------------------------------------------------------------------
  # EXCEL — download current results as a .xlsx Excel file
  # ---------------------------------------------------------------------------
  # `excel` is the Excel-format counterpart to `csv` above — same overall
  # shape, but building a real .xlsx spreadsheet file instead of plain text.
  def excel
    latest_crawl = CrawlRun.latest_completed

    unless latest_crawl
      flash[:alert] = "No crawl data to export. Run a crawl first."
      redirect_to root_path
      return
    end
    # `end` closes the `unless latest_crawl` block above.

    # Unlike `csv` above (which builds the file content directly in Ruby
    # and streams it with `send_data`), Excel generation here is done via a
    # VIEW TEMPLATE (app/views/exports/excel.xlsx.axlsx) — so `@units`
    # needs to be an instance variable (not just a local variable) so that
    # template can read it, the same way any other Rails view reads
    # instance variables set by its controller action.
    @units   = fetch_filtered_units(latest_crawl)
    filename = "storagefinder_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx"

    # The dashboard's "Excel" link is a plain <a href> with no format
    # specifier, so the browser sends Accept: text/html — without forcing
    # the format here, respond_to's format.xlsx block never matches and
    # every request raises ActionController::UnknownFormat. This endpoint
    # only ever serves xlsx, regardless of what the browser asked for.
    # `request.format = :xlsx` overrides Rails' automatic format detection
    # (normally based on the URL's file extension or the browser's Accept
    # header) and forces it to treat this request as asking for the
    # `:xlsx` format specifically — necessary because of the plain-link
    # issue explained in the comment above.
    request.format = :xlsx

    # The render call uses caxlsx_rails to process the Excel template
    # The template is at app/views/exports/excel.xlsx.axlsx
    # `caxlsx_rails` is a third-party gem (Ruby library) that lets Rails
    # render `.axlsx`-extension view templates into real binary .xlsx
    # spreadsheet files.
    respond_to do |format|
      # `format.xlsx { ... }` — because `request.format` was forced to
      # `:xlsx` above, this is the only branch that will ever run; there's
      # no `format.html` fallback here since this controller action is
      # xlsx-only.
      format.xlsx {
        # Sets the Content-Disposition response header directly (rather
        # than via `send_data`'s `disposition:` option, as `csv` did above)
        # — same effect: it tells the browser to download the response as
        # a file with this name, rather than displaying it inline.
        response.headers["Content-Disposition"] = "attachment; filename=#{filename}"
      }
      # `}` closes the `format.xlsx { ... }` block above. Note there's no
      # explicit `render` call inside it — Rails' default behavior (when no
      # `render`/`redirect_to` is called inside a `respond_to` block) is to
      # automatically render the template matching this action's name and
      # the negotiated format, i.e. app/views/exports/excel.xlsx.axlsx.
    end
    # `end` closes the `respond_to do |format| ... end` block above.

  rescue => e
    Rails.logger.error("[ExportsController] Excel export failed: #{e.class}: #{e.message}")
    flash[:alert] = "Excel export failed: #{e.message}"
    redirect_to root_path
  end
  # `end` closes the `def excel` action definition (the `rescue` clause
  # above is part of this same method).

  # ---------------------------------------------------------------------------
  # PRIVATE
  # ---------------------------------------------------------------------------
  private

  # Fetch units from the latest crawl with the same filters the dashboard uses
  # Takes the crawl_run to pull units from, and returns them pre-filtered
  # to match what the dashboard's default (climate-controlled, indoor,
  # available, standard-size) view would show — exports intentionally use a
  # FIXED filter set here rather than reading the dashboard's current
  # params, so an export always reflects the "clean" default view
  # regardless of whatever filters happen to be active on-screen.
  def fetch_filtered_units(crawl_run)
    # `.includes(:facility)` eager-loads each unit's Facility record up
    # front to avoid an N+1 query problem in `build_csv` below (see
    # DashboardController#results for a fuller explanation of eager
    # loading). Each `.where(...)` call chains another SQL condition onto
    # the query (query stays lazy/unexecuted until actually used).
    crawl_run.units
             .includes(:facility)
             .where(climate_controlled: true)
             .where(drive_up: false, indoor: true)
             .where(available: true)
             .where.not(unit_type: Unit::EXCLUDED_TYPES)
             .where(size: Unit::DEFAULT_SIZES)
             # `.order(:monthly_price)` sorts cheapest-first — the final
             # step in the chain, and this method's return value since it's
             # the chain's last expression.
             .order(:monthly_price)
  end
  # `end` closes the `def fetch_filtered_units` method definition opened above.

  # Build CSV content from a collection of units
  # Takes an ActiveRecord collection of units and returns a single String
  # containing the full CSV file content.
  def build_csv(units)
    # `require "csv"` loads Ruby's standard-library CSV module — needed
    # here because this file otherwise has no reason to have it already
    # loaded. (Unlike a Rails gem, Ruby's standard library isn't always
    # auto-loaded, so files that use it explicitly `require` it.)
    require "csv"

    # `CSV.generate(...) do |csv| ... end` builds a CSV-formatted string in
    # memory: it yields a `csv` object to the block, and every `csv << [...]`
    # call inside appends one more row. `headers: true` and `encoding:
    # "UTF-8"` are keyword arguments configuring the CSV generation (the
    # `headers: true` option here mainly documents intent — the actual
    # header row is added manually below via the first `csv << [...]`
    # call). The whole `CSV.generate` call's return value — the finished
    # CSV string — becomes this method's return value.
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      # Header row
      # `csv << [...]` appends an Array as one row — `<<` here is CSV's
      # "append" operator (not related to string/array `<<` used
      # elsewhere for concatenation, though it's the same Ruby operator,
      # just overloaded/redefined by the CSV class to mean "add a row").
      # Each string element becomes one column header.
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
      # `]` closes the header-row array literal above.

      # Data rows
      # `units.each do |unit| ... end` iterates over every unit in the
      # collection, running the block body once per unit — unlike `.map`
      # (used elsewhere in this app), `.each` doesn't build/return a new
      # array; it's used purely for its side effect here (appending CSV
      # rows).
      units.each do |unit|
        f = unit.facility  # Shorthand for facility
        # Appends one data row per unit, with values in the SAME ORDER as
        # the header row above (CSV format has no column names embedded
        # per-row — position is everything, so keeping this order in sync
        # with the header row above matters).
        csv << [
          f.company,
          f.name,
          f.address,
          f.city,
          f.state,
          f.zip,
          # `.formatted_phone` is a custom presentation method on Facility.
          f.formatted_phone,
          f.distance_miles,
          unit.size,
          unit.sqft,
          unit.monthly_price,
          unit.web_special_price,
          unit.web_special_note,
          unit.admin_fee,
          unit.insurance_note,
          # `? "Yes" : "No"` — a ternary turning the raw boolean predicate
          # methods into human-readable Yes/No text for the spreadsheet,
          # rather than Ruby's raw `true`/`false`.
          unit.climate_controlled? ? "Yes" : "No",
          unit.available? ? "Yes" : "No",
          unit.booking_url,
          # `&.strftime(...)` — safe navigation in case collected_at is
          # nil (unit never successfully scraped); formats as e.g.
          # "2026-07-18 14:30:00" (year-month-day hour:minute:second).
          unit.collected_at&.strftime("%Y-%m-%d %H:%M:%S")
        ]
        # `]` closes the data-row array literal for this unit.
      end
      # `end` closes the `units.each do |unit| ... end` loop above.
    end
    # `end` closes the `CSV.generate(...) do |csv| ... end` block above.
  end
  # `end` closes the `def build_csv` method definition opened above.
end
# `end` closes the `class ExportsController` definition opened at the top of
# the file.
