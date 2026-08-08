# =============================================================================
# PUBLIC SEARCH CONTROLLER
# =============================================================================
# The customer-facing search/comparison page — reachable by anyone with the
# URL, no credentials required. This is deliberately SEPARATE from every
# other controller in the app: it inherits directly from
# `ActionController::Base` instead of from ApplicationController, so it
# never picks up ApplicationController's `http_basic_authenticate_with`
# gate in the first place.
#
# Why not inherit from ApplicationController and try to "skip" the gate
# instead? `http_basic_authenticate_with` (see
# app/controllers/application_controller.rb) registers its check as an
# ANONYMOUS block passed to `before_action`, not a named method — Rails'
# `skip_before_action` can only skip a callback that was registered with a
# Symbol/method name it can look up later, so there is no supported way to
# selectively "opt out" of an anonymous block-based before_action from a
# subclass. The one working pattern is the one this app already uses for
# its other unauthenticated surface: PWA/health-check controllers (see the
# comments in config/routes.rb) and the JSON API under app/controllers/api/
# (see app/controllers/api/base_controller.rb) all bypass
# ApplicationController entirely by inheriting from a different base class
# instead. This controller follows that same established pattern — the
# API uses ActionController::API (no views/sessions needed for JSON), and
# this controller uses ActionController::Base (it renders real HTML pages).
# =============================================================================

class PublicSearchController < ActionController::Base
  # Uses its own layout (app/views/layouts/public.html.erb) instead of the
  # default application layout — the default layout's nav bar links to
  # Dashboard/Alert Rules/Settings, all admin pages behind HTTP Basic Auth,
  # which would be confusing (and mildly information-leaking) to show to an
  # anonymous customer on this public page.
  layout "public"

  # CSRF protection isn't strictly required for this controller's two
  # GET-only actions (no forms POST anywhere here), but it's cheap
  # insurance against this class picking up a form later without anyone
  # remembering to add it — matches the standard Rails default that
  # ApplicationController also sets.
  protect_from_forgery with: :exception

  # Same page-title convention as ApplicationController (see that file for
  # the full explanation) — duplicated here in miniature rather than
  # shared, since this controller intentionally does NOT inherit from
  # ApplicationController.
  helper_method :current_page_title

  # ---------------------------------------------------------------------------
  # INDEX — search + filter + compare facilities
  # ---------------------------------------------------------------------------
  # GET /search
  # Optional query params:
  #   city        — filter to a specific city (exact match, e.g. "Gilbert")
  #   lat / lng   — origin point for distance sorting/display (e.g. from the
  #                 browser's geolocation API, or a geocoded address)
  #   sizes[]     — restrict to specific unit sizes (e.g. "10x10", "10x20")
  #   min_price / max_price — monthly price range, inclusive
  #   sort        — "price" (default) or "distance" (requires lat/lng)
  #   dir         — "asc" (default) or "desc"
  def index
    @page_title = "Find Storage Near You — StorageFinder"

    @available_sizes = Unit::DEFAULT_SIZES
    @selected_sizes  = Array(params[:sizes]).reject(&:blank?)
    @city            = params[:city].presence
    @min_price       = params[:min_price].presence&.to_f
    @max_price       = params[:max_price].presence&.to_f

    @origin = origin_coordinates

    @facilities = build_facility_results

    @sort = %w[price distance].include?(params[:sort]) ? params[:sort] : "price"
    @dir  = params[:dir] == "desc" ? "desc" : "asc"

    apply_sort!
  end

  # ---------------------------------------------------------------------------
  # SHOW — one facility's detail page: current unit pricing & availability
  # ---------------------------------------------------------------------------
  # GET /search/:id
  def show
    @facility = Facility.find(params[:id])
    @page_title = "#{@facility.name} — StorageFinder"

    # `.available` and `.cheapest_first` are existing Unit scopes (see
    # app/models/unit.rb) — reused as-is rather than re-implementing the
    # same filtering/sorting logic here.
    @units = @facility.units.available.cheapest_first
  rescue ActiveRecord::RecordNotFound
    redirect_to public_search_path, alert: "That facility couldn't be found."
  end

  private

  def current_page_title
    @page_title || "StorageFinder"
  end

  # Reads an optional lat/lng origin point out of the params — used both to
  # sort by distance (via Facility.nearest_to) and to show a distance label
  # on each result card.
  def origin_coordinates
    return nil if params[:lat].blank? || params[:lng].blank?

    { lat: params[:lat].to_f, lng: params[:lng].to_f }
  end

  # Builds the filtered facility list. Filters by price/size first (via a
  # Unit query, reusing Unit's own scopes) to find which facilities have at
  # least one matching available unit, then filters/sorts Facility itself.
  def build_facility_results
    # `Unit.available` is an existing scope (see app/models/unit.rb) — the
    # same "available" definition Facility#cheapest_available_unit/#min_price
    # rely on, so the units driving this search match what the facility
    # cards below end up displaying as their starting price.
    unit_scope = Unit.available
    unit_scope = unit_scope.with_sizes(@selected_sizes) if @selected_sizes.present?
    unit_scope = unit_scope.where("monthly_price >= ?", @min_price) if @min_price
    unit_scope = unit_scope.where("monthly_price <= ?", @max_price) if @max_price

    matching_facility_ids = unit_scope.distinct.pluck(:facility_id)

    scope = Facility.where(id: matching_facility_ids).includes(:units)
    scope = scope.in_city(@city) if @city.present?
    scope = scope.nearest_to(@origin[:lat], @origin[:lng]) if @origin

    scope.to_a
  end

  # Applies the user's requested sort on top of whatever order
  # build_facility_results already produced. Distance sorting is handled by
  # Facility.nearest_to's SQL ORDER BY (see build_facility_results above) —
  # here we just reverse it for "desc", or fall back to price sorting if no
  # origin point was given (distance is meaningless without one).
  def apply_sort!
    if @sort == "distance" && @origin
      @facilities.reverse! if @dir == "desc"
      return
    end

    @sort = "price"
    # `min_price` is an existing Facility instance method (see
    # app/models/facility.rb) — reused here instead of re-deriving "cheapest
    # available unit's price" again.
    @facilities.sort_by! { |facility| facility.min_price || Float::INFINITY }
    @facilities.reverse! if @dir == "desc"
  end
end
