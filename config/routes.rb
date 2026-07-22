# =============================================================================
# ROUTES
# =============================================================================
# Routes define what URLs exist in the app and which controller/action handles each.
#
# Format: HTTP_VERB "url_path" => "controller#action"
#
# Example: get "/dashboard" => "dashboard#index"
#          means: GET requests to /dashboard are handled by DashboardController#index
# =============================================================================

Rails.application.routes.draw do
  # ---------------------------------------------------------------------------
  # HEALTH CHECK — used by Kamal's proxy to know when a deployed container is
  # ready to receive traffic. Rails::HealthController inherits directly from
  # ActionController::Base (not our ApplicationController), so it's reachable
  # without HTTP Basic Auth credentials — which Kamal's health probe doesn't send.
  # ---------------------------------------------------------------------------
  get "up" => "rails/health#show", as: :rails_health_check

  # ---------------------------------------------------------------------------
  # ROOT — the main page when you visit storagefinder.local
  # ---------------------------------------------------------------------------
  root "dashboard#index"   # GET / → DashboardController#index

  # ---------------------------------------------------------------------------
  # DASHBOARD
  # ---------------------------------------------------------------------------
  get  "dashboard",         to: "dashboard#index",    as: :dashboard
  get  "dashboard/status",  to: "dashboard#status",   as: :dashboard_status   # JSON: is crawl running?
  get  "dashboard/results", to: "dashboard#results",  as: :dashboard_results  # JSON: unit results table

  # ---------------------------------------------------------------------------
  # CRAWLS
  # ---------------------------------------------------------------------------
  resources :crawls, only: [ :create, :show, :destroy ] do
    member do
      get "log"   # GET /crawls/:id/log — JSON log entries for live progress feed
    end
    collection do
      delete "destroy_selected"   # DELETE /crawls/destroy_selected — bulk-delete checked history rows
    end
  end

  # ---------------------------------------------------------------------------
  # EXPORTS
  # ---------------------------------------------------------------------------
  # Note: Using `scope` not `namespace` so the URL is /exports/csv but the
  # controller is still ExportsController (not Exports::ExportsController)
  scope "/exports", as: "exports" do
    get "csv",   to: "exports#csv",   as: :csv    # Download /exports/csv
    get "excel", to: "exports#excel", as: :excel  # Download /exports/excel
  end

  # ---------------------------------------------------------------------------
  # SETTINGS
  # ---------------------------------------------------------------------------
  get "settings", to: "settings#index", as: :settings
  resource :settings, only: [ :update ] do
    post "test_email",   to: "settings#test_email",   as: :test_email
    post "test_discord", to: "settings#test_discord", as: :test_discord
  end

  # ---------------------------------------------------------------------------
  # ALERT RULES
  # ---------------------------------------------------------------------------
  resources :alert_rules  # Full CRUD: index, show, new, create, edit, update, destroy

  # ---------------------------------------------------------------------------
  # ACTION CABLE — WebSocket endpoint for live crawl progress
  # ---------------------------------------------------------------------------
  mount ActionCable.server => "/cable"
end
