# =============================================================================
# API BASE CONTROLLER
# =============================================================================
# Base class for every controller under app/controllers/api/. Deliberately
# inherits directly from ActionController::API rather than from
# ApplicationController — ApplicationController wraps every action behind
# HTTP Basic Auth meant for a human with a browser (see
# app/controllers/application_controller.rb), which isn't appropriate for a
# JSON API consumed by scripts. Instead, every action here is authenticated
# by an ApiKey token (see app/models/api_key.rb) passed in an
# "Authorization: Bearer <token>" header.
#
# `ActionController::API` (vs. ActionController::Base) is Rails' lighter
# base class for API-only controllers: it skips middleware/behavior only
# relevant to rendering HTML views and managing browser sessions/cookies
# (e.g. CSRF token verification, flash messages) that a token-authenticated
# JSON client never uses.
# =============================================================================

module Api
  class BaseController < ActionController::API
    # Raised by a subclass action (or one of its private helpers, e.g.
    # FacilitiesController#origin_coordinates) when a query param is
    # present but not usable, a non-numeric `lat`/`lng`/`max_price`, for
    # example. Kept as a real, named exception (rather than each action
    # rendering the error itself and remembering to `return` right after)
    # so raising it from a deeply-nested private helper still reliably
    # produces one clean JSON error response, the same reasoning that
    # already applies to ActiveRecord::RecordNotFound below.
    class InvalidParameter < StandardError; end

    before_action :authenticate_api_key!
    after_action :record_api_key_usage

    # Rails raises ActiveRecord::RecordNotFound when a `find` can't locate a
    # row (e.g. GET /api/v1/facilities/999999). Left unhandled, that would
    # bubble up into Rails' generic 500-style error page; rescuing it here
    # and rendering JSON keeps every response from this API consistently
    # JSON-shaped instead of occasionally leaking an HTML error page.
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from InvalidParameter, with: :render_bad_request

    private

    # Shared pagination helpers, identical rules for every list endpoint
    # under app/controllers/api/v1/ (previously duplicated verbatim in
    # FacilitiesController and UnitsController).
    def page_limit
      [ params.fetch(:limit, 50).to_i, 100 ].min.clamp(1, 100)
    end

    def page_offset
      [ params.fetch(:offset, 0).to_i, 0 ].max
    end

    # Accepts the token either as a standard Bearer Authorization header
    # (preferred: `Authorization: Bearer <token>`) or as an `api_key` query
    # parameter (simpler for quick testing in a browser address bar or a
    # tool that can't easily set custom headers).
    def authenticate_api_key!
      token = bearer_token || params[:api_key]
      @current_api_key = ApiKey.active.find_by(token: token) if token.present?

      return if @current_api_key

      render json: { error: "Missing or invalid API key. Pass it as 'Authorization: Bearer <token>' or '?api_key=<token>'." },
             status: :unauthorized
    end

    def bearer_token
      header = request.headers["Authorization"]
      return nil unless header

      # `Authorization: Bearer abc123` — split on whitespace, take the part
      # after the scheme name.
      scheme, token = header.split(" ", 2)
      token if scheme&.casecmp("Bearer")&.zero?
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def render_bad_request(error)
      render json: { error: error.message }, status: :bad_request
    end

    # Bumps last_used_at/request_count once per successfully-authenticated
    # request. Runs as an `after_action` (rather than inline in
    # authenticate_api_key!) so it only fires when a request actually made
    # it past authentication and ran a real action.
    def record_api_key_usage
      current_api_key&.record_usage!
    end

    attr_reader :current_api_key
  end
end
