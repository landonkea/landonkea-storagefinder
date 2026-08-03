# =============================================================================
# DASHBOARD CONTROLLER
# =============================================================================
# Handles the main dashboard page where users:
#   - See current storage unit results
#   - Set filter options
#   - Run crawls
#   - View price history graphs
# =============================================================================

# `class DashboardController < ApplicationController` — see
# app/controllers/application_controller.rb for what "controller" and
# "inherits from" mean.
class DashboardController < ApplicationController
  # ---------------------------------------------------------------------------
  # INDEX — the main dashboard page
  # ---------------------------------------------------------------------------
  # `index` is the conventional action name for a resource's main/landing
  # page — here, the whole app's home page (GET /).
  def index
    @page_title = "Dashboard — StorageFinder"

    # -------------------------------------------------------------------------
    # Load the most recent crawl run (if any)
    # -------------------------------------------------------------------------
    # `CrawlRun.latest_completed` is a custom model method (likely a scope
    # or class method defined on CrawlRun) that returns the most recently
    # finished crawl, or nil if none has ever completed.
    @latest_crawl = CrawlRun.latest_completed

    # Is a crawl currently running?
    # `.any_running?` returns true/false for whether any crawl is currently
    # in progress (see CrawlsController#create for the same check used to
    # block starting a second crawl).
    @crawl_running = CrawlRun.any_running?
    # `CrawlRun.running` is presumably a scope returning all in-progress
    # crawl records; `.first` takes just the first one (there should only
    # ever be zero or one, since a second crawl is blocked from starting).
    @running_crawl = CrawlRun.running.first

    # -------------------------------------------------------------------------
    # Build the results query from the latest crawl
    # -------------------------------------------------------------------------
    # Only attempt to build a results query if a crawl has actually
    # completed at least once — otherwise there's nothing to query.
    if @latest_crawl
      # Delegates to the private `build_results_query` method below, which
      # applies all the filter/sort params to construct the query.
      @units = build_results_query(@latest_crawl)
    else
      # `Unit.none` is ActiveRecord's way of representing "an empty result
      # set that behaves like a real query" (as opposed to just `nil` or
      # `[]`) — so views can still safely call query methods like `.each`
      # or `.count` on it without special-casing "no crawl yet."
      @units = Unit.none  # Empty — no crawl has been run yet
    end
    # `end` closes the `if @latest_crawl ... else ... end` block above.

    # -------------------------------------------------------------------------
    # Filter options for the UI
    # -------------------------------------------------------------------------
    # `CompanyRegistry.all_company_names` returns every storage company this
    # app knows how to crawl, used to populate the company-filter checkboxes.
    @available_companies = CompanyRegistry.all_company_names
    # `Unit::DEFAULT_SIZES` is a constant on the Unit model listing which
    # unit sizes are shown/searched by default.
    @available_sizes     = Unit::DEFAULT_SIZES
    # `Unit.all_sizes` is a custom model method returning every DISTINCT
    # size value actually present in the units table (as opposed to
    # DEFAULT_SIZES, which is a fixed, hardcoded list) — used so the UI can
    # offer filters for sizes that genuinely exist in the data.
    @all_sizes_in_db     = Unit.all_sizes  # Sizes actually found in the database

    # Selected filters (from the URL params, or defaults)
    # `params[:sizes]` would arrive here as a comma-separated string (e.g.
    # "5x5,10x10") when navigating via a URL query string (contrast with
    # CrawlsController#create, where sizes[] arrives as a real array from
    # checkboxes in a form POST — these are two different code paths).
    # `&.split(",")` (safe navigation, see CrawlsController for what `&.`
    # does) splits that string into an array, or evaluates to nil if
    # params[:sizes] itself is nil; `||` then falls back to the default
    # size list.
    @selected_sizes      = params[:sizes]&.split(",") || Unit::DEFAULT_SIZES
    # Same "default true unless explicitly false" pattern seen in
    # CrawlsController#create.
    @climate_only        = params[:climate_only] != "false"   # Default: true
    @selected_companies  = params[:companies]&.split(",") || @available_companies
    # `||` provides fallback default values when no sort params were given
    # in the URL — defaulting to sorting by price, ascending (cheapest
    # first).
    @sort_by             = params[:sort] || "monthly_price"
    @sort_dir             = params[:dir] || "asc"

    # -------------------------------------------------------------------------
    # Price history data for the trend chart
    # -------------------------------------------------------------------------
    @price_history = build_price_history

    # -------------------------------------------------------------------------
    # Average price by company, unit availability by size, and crawl
    # success/failure rate — data for the extra dashboard charts.
    # -------------------------------------------------------------------------
    @avg_price_by_company    = build_avg_price_by_company
    @unit_availability_by_size = build_unit_availability_by_size
    @crawl_status_by_day     = build_crawl_status_by_day

    # -------------------------------------------------------------------------
    # Crawl history for the history panel
    # -------------------------------------------------------------------------
    # `Setting.get("history_keep_months", default: 6)` reads a user-
    # configurable app setting (see SettingsController) with a fallback
    # default value of 6 if it was never explicitly set; `.to_i` converts
    # whatever's stored (likely a string, since Settings are typically
    # stored as text) into an integer.
    history_months = Setting.get("history_keep_months", default: 6).to_i
    # `CrawlRun.history(months: ...)` is a custom model method returning
    # crawl records from within the last N months; `.limit(20)` caps the
    # result to at most 20 rows so the history panel doesn't grow unbounded.
    @crawl_history  = CrawlRun.history(months: history_months).limit(20)
  end
  # `end` closes the `def index` action definition opened above.

  # ---------------------------------------------------------------------------
  # STATUS — JSON endpoint for live crawl status polling
  # The JavaScript on the dashboard calls this to check if a crawl is still running
  # ---------------------------------------------------------------------------
  # `status` is a custom action (needs an explicit route) returning a small
  # JSON snapshot of crawl state, polled repeatedly by dashboard JavaScript.
  def status
    running = CrawlRun.any_running?
    latest  = CrawlRun.latest_completed

    render json: {
      crawl_running:    running,
      # `&.id` — safe navigation again: if no crawl is running,
      # `CrawlRun.running.first` is nil, and `nil&.id` evaluates to nil
      # rather than raising an error, so this key becomes JSON `null`.
      running_crawl_id: CrawlRun.running.first&.id,
      latest_crawl: {
        # Every field below uses `&.` because `latest` itself may be nil
        # (no crawl has ever completed) — each lookup safely becomes nil/
        # JSON `null` in that case instead of crashing the whole response.
        id:               latest&.id,
        status:           latest&.status,
        facilities_found: latest&.facilities_found,
        units_found:      latest&.units_found,
        # `&.completed_at&.iso8601` chains TWO safe-navigation calls: first
        # in case `latest` is nil, second in case `completed_at` itself is
        # nil (e.g. a crawl that's marked latest but hasn't technically
        # finished) — `.iso8601` formats a Ruby Time as a standard
        # ISO 8601 string (e.g. "2026-07-18T10:30:00-05:00") for JSON/
        # JavaScript to parse easily.
        completed_at:     latest&.completed_at&.iso8601
      }
      # `}` closes the nested `latest_crawl: { ... }` hash.
    }
    # `}` closes the `render json: { ... }` hash argument.
  end
  # `end` closes the `def status` action definition opened above.

  # ---------------------------------------------------------------------------
  # RESULTS — JSON endpoint that returns the filtered unit results table
  # Called via AJAX when filters change or a crawl finishes
  # ---------------------------------------------------------------------------
  # `results` is another custom JSON-only action, returning the actual unit
  # listing data (as opposed to `status`, which returns only summary info).
  def results
    latest_crawl = CrawlRun.latest_completed

    # `unless latest_crawl` runs its block only when `latest_crawl` is nil/
    # false — i.e. no crawl has ever completed.
    unless latest_crawl
      render json: { units: [], message: "No crawl data yet. Run a crawl to see results." }
      return
    end
    # `end` closes the `unless latest_crawl` block above.

    units = build_results_query(latest_crawl)

    # Build a simple array of unit data for the JSON response
    # `.includes(:facility)` is ActiveRecord "eager loading" — it fetches
    # every unit's associated Facility record in one extra batch query up
    # front, instead of running a separate database query for
    # `unit.facility` inside the `.map` block below for EVERY unit (which
    # would otherwise cause a slow "N+1 query" problem — one query per
    # unit, on top of the one query for the units themselves).
    unit_data = units.includes(:facility).map do |unit|
      {
        id:                 unit.id,
        company:            unit.facility.company,
        facility_name:      unit.facility.name,
        # `.full_address` / `.distance_miles` / `.formatted_phone` /
        # `.maps_url` are custom presentation methods defined on the
        # Facility model, formatting raw database columns for display.
        address:            unit.facility.full_address,
        city:                unit.facility.city,
        distance_miles:     unit.facility.distance_miles,
        phone:              unit.facility.formatted_phone,
        size:               unit.size,
        sqft:               unit.sqft,
        monthly_price:      unit.monthly_price,
        web_special_price:  unit.web_special_price,
        web_special_note:   unit.web_special_note,
        # `.best_price` / `.price_color_class` are custom methods on the
        # Unit model computing the cheaper of monthly vs. web-special price,
        # and a CSS class name reflecting how good that price is.
        best_price:         unit.best_price,
        price_color:        unit.price_color_class,
        # `.climate_controlled?` / `.available?` are predicate methods
        # (Ruby convention: `?`-suffixed methods return true/false)
        # reflecting the corresponding boolean database columns.
        climate_controlled: unit.climate_controlled?,
        available:          unit.available?,
        booking_url:        unit.booking_url,
        maps_url:           unit.facility.maps_url,
        # `&.strftime(...)` — safe navigation again, since `collected_at`
        # could be nil if this unit's price was never actually scraped
        # successfully; formats as e.g. "Jul 18 at 03:45 PM" for display.
        collected_at:       unit.collected_at&.strftime("%b %d at %I:%M %p")
      }
    end
    # `end` closes the `units.includes(:facility).map do |unit| ... end`
    # block above — its return value (the array of hashes built by each
    # iteration) is stored in `unit_data`.

    render json: { units: unit_data, total: unit_data.length }
  end
  # `end` closes the `def results` action definition opened above.

  # ---------------------------------------------------------------------------
  # PRIVATE HELPERS
  # ---------------------------------------------------------------------------
  # `private` marks every method below as internal-only — not reachable as
  # a URL/action, just implementation details supporting the public actions
  # above.
  private

  # Builds the ActiveRecord query for results based on current filter params
  # Takes the crawl_run whose units should be queried, and progressively
  # narrows the query down using whatever filter params are present in the
  # current request.
  def build_results_query(crawl_run)
    # `crawl_run.units` is the association of Unit records belonging to
    # this crawl; `.includes(:facility)` eager-loads each unit's Facility
    # (see the `results` action above for why that matters). Note:
    # ActiveRecord queries are "lazy" — none of this actually hits the
    # database until the query is used (e.g. iterated, counted, or
    # rendered) — each `.where(...)` below just adds another condition to
    # the query being built up, without running it yet.
    query = crawl_run.units.includes(:facility)

    # Apply climate controlled filter
    # Same "default true unless explicitly false" pattern used elsewhere.
    if params[:climate_only] != "false"
      # `.where(climate_controlled: true)` adds a SQL WHERE condition;
      # re-assigning `query =` chains it onto the existing query (each
      # `.where` call returns a NEW query object rather than modifying the
      # old one in place, so the reassignment is necessary to keep the
      # added condition).
      query = query.where(climate_controlled: true)
    end
    # `end` closes the `if params[:climate_only] != "false"` block above.

    # Apply size filter
    if params[:sizes].present?
      selected_sizes = params[:sizes].split(",")
      # `.where(size: selected_sizes)` with an ARRAY value generates a SQL
      # "IN" condition — matching any unit whose size is one of the listed
      # values.
      query = query.where(size: selected_sizes)
    else
      query = query.where(size: Unit::DEFAULT_SIZES)
    end
    # `end` closes the `if params[:sizes].present? ... else ... end` block.

    # Apply company filter
    if params[:companies].present?
      selected_companies = params[:companies].split(",")
      # `.joins(:facility)` adds a SQL JOIN to the facilities table (needed
      # because "company" is a column on Facility, not on Unit itself), so
      # the following `.where(facilities: { company: ... })` can filter by
      # it — the hash-of-a-hash syntax `facilities: { company: ... }` tells
      # ActiveRecord to scope the `company` condition to the joined
      # `facilities` table specifically, avoiding ambiguity if `units` had
      # its own `company` column too.
      query = query.joins(:facility).where(facilities: { company: selected_companies })
    end
    # `end` closes the `if params[:companies].present?` block above (there's
    # no `else` — if no companies were specified, the query is left
    # unfiltered by company, matching every company).

    # Exclude non-standard unit types
    # `.where.not(...)` is ActiveRecord's negated WHERE — generates a SQL
    # "NOT IN" condition here, excluding any unit whose type is in the
    # EXCLUDED_TYPES list (e.g. parking spaces, vehicle storage).
    query = query.where.not(unit_type: Unit::EXCLUDED_TYPES)

    # Only indoor, non-drive-up units
    # Hardcoded, non-optional filter — always restricts results to
    # indoor, non-drive-up units regardless of what the user selected.
    query = query.where(drive_up: false, indoor: true)

    # Only available units (can be toggled off via params)
    # `unless params[:include_unavailable] == "true"` means: apply the
    # `available: true` filter UNLESS the request explicitly asked to
    # include unavailable units too.
    query = query.where(available: true) unless params[:include_unavailable] == "true"

    # Apply sorting
    # `sanitize_sort_column` (defined below) validates the requested sort
    # column against an allowlist before it's used to build a raw SQL
    # string — this matters because directly interpolating user input into
    # SQL (as the `.order(...)` call below does) would otherwise be a SQL-
    # injection risk.
    sort_column = sanitize_sort_column(params[:sort] || "monthly_price")
    # `== "desc" ? "desc" : "asc"` is a ternary expression: if the dir param
    # is exactly "desc", use "desc"; otherwise (missing, or any other
    # value) default to ascending order.
    sort_dir    = params[:dir] == "desc" ? "desc" : "asc"

    # Applies the final sort. `"#{sort_column} #{sort_dir}"` builds a raw
    # SQL ORDER BY fragment like "monthly_price asc" — safe here ONLY
    # because sort_column was validated against a fixed allowlist above
    # (sort_dir is separately constrained to exactly "asc" or "desc" by the
    # ternary above), so no untrusted text reaches the SQL string.
    query.order("#{sort_column} #{sort_dir}")
    # No explicit `return` — this is the method's last expression, so its
    # value (the final, fully-filtered-and-sorted query) is what
    # `build_results_query` returns to its caller.
  end
  # `end` closes the `def build_results_query` method definition opened above.

  # Prevent SQL injection in sort column by whitelisting allowed columns
  def sanitize_sort_column(column)
    # `%w[...]` is Ruby's "word array" literal shorthand — equivalent to
    # writing `["monthly_price", "sqft", "facilities.distance_miles",
    # "facilities.company", "size"]`, but without needing quotes/commas
    # around each word.
    allowed = %w[monthly_price sqft facilities.distance_miles facilities.company size]
    # `.include?(column)` checks whether `column` (the untrusted, user-
    # supplied value) exactly matches one of the allowed strings. The
    # ternary returns `column` itself if it's allowed, or the safe default
    # "monthly_price" otherwise — this is what makes it safe to later
    # interpolate `sort_column` directly into a raw SQL string in
    # `build_results_query` above.
    allowed.include?(column) ? column : "monthly_price"
  end
  # `end` closes the `def sanitize_sort_column` method definition opened above.

  # Build price history data for the trend chart
  # Returns data grouped by week for the last 6 months
  def build_price_history
    # Reads the same configurable "how many months of history to keep"
    # setting used in the `index` action above.
    months_back = Setting.get("history_keep_months", default: 6).to_i

    # Builds a chained ActiveRecord query, one `.where`/method call per
    # line (Ruby allows a method chain to be split across lines as long as
    # each line ends with a method-call dot, signaling "more to come" on
    # the next line).
    Unit.where("collected_at >= ?", months_back.months.ago)
        # `months_back.months.ago` — `.months` is a Rails-added method on
        # Integer that turns a plain number into a duration (e.g. `6.months`
        # is "a span of 6 months"); `.ago` then converts that duration into
        # an actual Time value that far in the past from right now. Used
        # with the `?` placeholder above to safely filter to only recent
        # units.
        .where(size: Unit::DEFAULT_SIZES)
        .where(climate_controlled: true)
        # `.where.not(monthly_price: nil)` excludes units where the price
        # was never successfully collected (nil), since averaging those in
        # would be meaningless/incorrect.
        .where.not(monthly_price: nil)
        # `.group_by_week(:collected_at)` is a Rails/Groupdate-style helper
        # bucketing rows into weekly groups based on the `collected_at`
        # timestamp column.
        .group_by_week(:collected_at)
        # `.average(:monthly_price)` computes the average monthly_price
        # WITHIN each weekly group (rather than one single average across
        # everything), producing a hash of { week => average_price } —
        # this is the method's return value, since it's the last expression
        # (the whole chained query is one big expression whose result is
        # implicitly returned).
        .average(:monthly_price)
  # `rescue => e` catches ANY StandardError (the bare `rescue` with no
  # specific error class defaults to catching StandardError and its
  # subclasses) raised anywhere in this method body — used broadly here
  # since a chart-building failure shouldn't crash the whole dashboard page.
  rescue => e
    Rails.logger.warn("[DashboardController] Could not build price history: #{e.message}")
    # On failure, return an empty hash instead of crashing — the trend
    # chart view can presumably handle "no data" gracefully. This is the
    # rescue block's last expression, so it becomes this method's return
    # value when the rescue path is taken.
    {}
  end
  # `end` closes the `def build_price_history` method definition (the
  # `rescue` clause above is part of this same method).

  # Build average monthly price per company for the bar chart.
  # Scoped to the latest completed crawl's units, same "real, priced,
  # standard" filters as build_price_history above, so the bar chart and
  # line chart agree on what counts as a valid priced unit.
  def build_avg_price_by_company
    return {} unless @latest_crawl

    @latest_crawl.units
        .joins(:facility)
        .where(size: Unit::DEFAULT_SIZES)
        .where(climate_controlled: true)
        .where.not(monthly_price: nil)
        # `.group("facilities.company")` groups by the company column on
        # the JOINED facilities table (same pattern as build_results_query's
        # company filter above) rather than a column on units itself.
        .group("facilities.company")
        .average(:monthly_price)
  rescue => e
    Rails.logger.warn("[DashboardController] Could not build avg price by company: #{e.message}")
    {}
  end

  # Build a count of currently-available units per size for the pie chart.
  # Scoped to the latest completed crawl, since availability is only
  # meaningful for the most recent snapshot of the market.
  def build_unit_availability_by_size
    return {} unless @latest_crawl

    @latest_crawl.units
        .where(available: true)
        .group(:size)
        .count
  rescue => e
    Rails.logger.warn("[DashboardController] Could not build unit availability by size: #{e.message}")
    {}
  end

  # Build crawl success/failure counts per day for the last 30 days.
  # CrawlRun doesn't track a per-company companies_crawled/companies_failed
  # split by day — those two columns are just running counters on ONE crawl
  # row (see CrawlRun#increment_companies_crawled!/#increment_companies_failed!).
  # The closest "success/failure rate over time" signal at the CrawlRun
  # level is each run's own terminal `status` ("completed" vs "failed"), so
  # this groups by status and by day. `.group(:status)` combined with
  # `.group_by_day(:created_at)` produces a Hash keyed by [status, day] that
  # chartkick/groupdate render as one line per status.
  def build_crawl_status_by_day
    CrawlRun
      .where(status: %w[completed failed])
      .group(:status)
      .group_by_day(:created_at, last: 30)
      .count
  rescue => e
    Rails.logger.warn("[DashboardController] Could not build crawl status by day: #{e.message}")
    {}
  end
end
# `end` closes the `class DashboardController` definition opened at the top
# of the file.
