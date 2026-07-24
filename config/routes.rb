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
# (The banner above is the file's original top-of-file documentation — kept
# as-is. One more mechanic worth spelling out for a novice: a "route" is
# just a rule Rails checks, in order, top to bottom, against the incoming
# request's HTTP method (GET/POST/PATCH/DELETE/etc.) and URL path. The
# first rule that matches wins and Rails calls that controller's action
# method. "as: :some_name" (seen throughout this file) additionally gives
# that route a name, so elsewhere in the app you can write
# `dashboard_path` or `dashboard_url` instead of hardcoding "/dashboard".)

# `Rails.application.routes.draw` opens Rails' routing DSL (Domain Specific
# Language — custom method calls like `get`, `resources`, `scope`, `mount`
# below that only make sense inside this block). Everything from here down
# to the matching `end` at the bottom of the file is the block passed to
# `.draw`, and it's where every URL this app responds to gets declared.
Rails.application.routes.draw do
  # ---------------------------------------------------------------------------
  # HEALTH CHECK — used by Kamal's proxy to know when a deployed container is
  # ready to receive traffic. Rails::HealthController inherits directly from
  # ActionController::Base (not our ApplicationController), so it's reachable
  # without HTTP Basic Auth credentials — which Kamal's health probe doesn't send.
  # ---------------------------------------------------------------------------
  # `get "up" => "rails/health#show"` declares a route: an HTTP GET request
  # to the path "/up" is handled by the `show` action of the built-in
  # `Rails::HealthController` (this controller ships with Rails itself, you
  # didn't write it — "rails/health" is its namespaced controller name, and
  # "#show" picks which action/method on it to call). `as: :rails_health_check`
  # names this route `rails_health_check`, so code elsewhere could call
  # `rails_health_check_path` to get "/up" without hardcoding the string.
  get "up" => "rails/health#show", as: :rails_health_check

  # ---------------------------------------------------------------------------
  # PWA — dynamically-rendered files a browser looks for to treat this app as
  # an installable "Progressive Web App" (add-to-home-screen icon, etc.).
  # Rails::PwaController (built into Rails, like Rails::HealthController
  # above) renders app/views/pwa/manifest.json.erb and
  # app/views/pwa/service-worker.js — those two view files already existed in
  # this app, but with no routes pointing at them a browser had no way to
  # ever request either one. `as: :pwa_manifest` names the manifest route so
  # the layout below can link to it via `pwa_manifest_path` instead of a
  # hardcoded string.
  # ---------------------------------------------------------------------------
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ---------------------------------------------------------------------------
  # ROOT — the main page when you visit storagefinder.local
  # ---------------------------------------------------------------------------
  # `root` is a special routing method: it defines what happens for a GET
  # request to "/" (the site's bare root URL, with no path at all). Here
  # it's set to the string "dashboard#index" — shorthand meaning "route to
  # DashboardController's index action." This single line implicitly also
  # creates a named route you can reference as `root_path`/`root_url`.
  root "dashboard#index"   # GET / → DashboardController#index

  # ---------------------------------------------------------------------------
  # DASHBOARD
  # ---------------------------------------------------------------------------
  # `get "dashboard", to: "dashboard#index", as: :dashboard` is the same
  # kind of rule as the `root` line above, but written in the more explicit
  # `to:`/`as:` keyword-argument style rather than the `"path" => "..."`
  # hash-rocket style used for the health check above — both forms mean the
  # same thing in Rails routing, this file just uses different styles in
  # different sections. This handles GET "/dashboard" via
  # DashboardController#index, and names the route `dashboard` (so
  # `dashboard_path` works).
  get  "dashboard",         to: "dashboard#index",    as: :dashboard
  # Handles GET "/dashboard/status" via DashboardController#status. The
  # trailing comment notes this endpoint returns JSON (not an HTML page) —
  # used by the frontend to poll whether a crawl is currently running.
  get  "dashboard/status",  to: "dashboard#status",   as: :dashboard_status   # JSON: is crawl running?
  # Handles GET "/dashboard/results" via DashboardController#results —
  # another JSON endpoint, this one returning the table of found storage
  # unit results, likely polled/refreshed by JavaScript on the page.
  get  "dashboard/results", to: "dashboard#results",  as: :dashboard_results  # JSON: unit results table

  # ---------------------------------------------------------------------------
  # CRAWLS
  # ---------------------------------------------------------------------------
  # `resources :crawls` is Rails' shorthand for generating a whole family of
  # RESTful routes (index/show/new/create/edit/update/destroy) for a
  # resource named "crawls", mapped to CrawlsController. `only: [ :create,
  # :show, :destroy ]` restricts it to JUST those three actions — no
  # index/new/edit/update routes get created, because this app apparently
  # only needs to start a crawl (create), view one (show), and remove it
  # (destroy). The `[ :create, :show, :destroy ]` is a Ruby Array literal
  # containing three Symbols (Ruby's lightweight, immutable name/label
  # type, written with a leading colon).
  resources :crawls, only: [ :create, :show, :destroy ] do
    # `member do ... end` nests additional routes UNDER this resource, but
    # scoped to a SPECIFIC crawl record (Rails automatically adds an `:id`
    # segment to the URL, since a "member" route always needs to know which
    # one). Routes declared inside apply only when working with one
    # particular crawl.
    member do
      # `get "log"` inside a `member` block becomes GET
      # "/crawls/:id/log" — routed to CrawlsController#log. No `to:` is
      # given, so Rails infers the action name from the string "log"
      # itself (this only works because the string matches a real method
      # name convention — explicit `to:` isn't required for member/
      # collection routes the way it is for top-level custom routes).
      get "log"   # GET /crawls/:id/log — JSON log entries for live progress feed
    end
    # `end` closes the `member do` block above — no more per-record routes
    # follow it.

    # `collection do ... end` is like `member`, but scoped to the crawls
    # resource AS A WHOLE (no specific `:id` in the URL) — for actions that
    # operate on the collection, like bulk-deleting several crawl records
    # at once.
    collection do
      # Declares DELETE "/crawls/destroy_selected", routed to
      # CrawlsController#destroy_selected — used to remove multiple
      # checked history rows in one request rather than one delete per row.
      delete "destroy_selected"   # DELETE /crawls/destroy_selected — bulk-delete checked history rows
    end
    # `end` closes the `collection do` block above.
  end
  # `end` closes the `resources :crawls do` block opened above — everything
  # between that line and here is nested under the crawls resource.

  # ---------------------------------------------------------------------------
  # EXPORTS
  # ---------------------------------------------------------------------------
  # Note: Using `scope` not `namespace` so the URL is /exports/csv but the
  # controller is still ExportsController (not Exports::ExportsController)
  # (Comment above is original/pre-existing and already explains the WHY —
  # kept as-is. Mechanically: `namespace` in Rails routing would change
  # BOTH the URL prefix AND the expected controller's Ruby module
  # namespace, e.g. requiring an `Exports::ExportsController` class nested
  # inside an `Exports` module. `scope`, used here instead, changes only
  # the URL prefix/route-name prefix, leaving the controller lookup as a
  # plain top-level `ExportsController` — deliberately avoiding having to
  # create that extra nesting for just two actions.)
  # `scope "/exports", as: "exports" do` prefixes every route declared
  # inside this block with "/exports" in the URL, and with "exports_" in
  # the generated route-helper names (e.g. `exports_csv_path` below).
  scope "/exports", as: "exports" do
    # Declares GET "/exports/csv", routed to ExportsController#csv, named
    # (after the scope's "exports" prefix is applied) `exports_csv` — so
    # `exports_csv_path` works elsewhere in the app.
    get "csv",   to: "exports#csv",   as: :csv    # Download /exports/csv
    # Declares GET "/exports/excel", routed to ExportsController#excel,
    # named `exports_excel` the same way.
    get "excel", to: "exports#excel", as: :excel  # Download /exports/excel
  end
  # `end` closes the `scope "/exports" do` block opened above.

  # ---------------------------------------------------------------------------
  # SETTINGS
  # ---------------------------------------------------------------------------
  # Declares GET "/settings", routed to SettingsController#index, named
  # `settings` — the page for viewing/editing app settings.
  get "settings", to: "settings#index", as: :settings
  # `resource :settings` (singular, unlike `resources :crawls` above) is
  # Rails' shorthand for a resource that has exactly ONE instance with no
  # `:id` needed in the URL (there's only ever one settings record/concept
  # for this app, not a list of many). `only: [ :update ]` restricts it to
  # just the update action, meaning this generates a PATCH/PUT
  # "/settings" route handled by SettingsController#update (the GET
  # "/settings" index route above was declared manually instead, since
  # plain `resource` with `only: [:update]` wouldn't include it).
  resource :settings, only: [ :update ] do
    # `post "test_email", to: "settings#test_email", as: :test_email`
    # nested inside `resource :settings do` becomes POST
    # "/settings/test_email", routed to SettingsController#test_email —
    # presumably a button that sends a test notification email using
    # currently-saved settings.
    post "test_email",   to: "settings#test_email",   as: :test_email
    # Same pattern: POST "/settings/test_discord", routed to
    # SettingsController#test_discord — sends a test Discord notification.
    post "test_discord", to: "settings#test_discord", as: :test_discord
  end
  # `end` closes the `resource :settings do` block opened above.

  # ---------------------------------------------------------------------------
  # ALERT RULES
  # ---------------------------------------------------------------------------
  # `resources :alert_rules` with no `only:` restriction generates the FULL
  # standard set of seven RESTful routes (index, show, new, create, edit,
  # update, destroy) for AlertRulesController — full create/read/update/
  # delete management of alert rule records, unlike the trimmed-down
  # `resources :crawls` above.
  resources :alert_rules  # Full CRUD: index, show, new, create, edit, update, destroy

  # ---------------------------------------------------------------------------
  # ACTION CABLE — WebSocket endpoint for live crawl progress
  # ---------------------------------------------------------------------------
  # `mount` attaches an entire separate Rack application (not a single
  # controller action) at a given URL path. `ActionCable.server` is Rails'
  # built-in WebSocket server application (WebSockets keep a connection
  # open for real-time, two-way updates — e.g. live crawl progress pushed
  # to the browser — unlike normal HTTP request/response). Mounting it at
  # "/cable" means any WebSocket connection to that path is handed off to
  # Action Cable instead of the normal routing/controller system.
  mount ActionCable.server => "/cable"
end
# `end` closes the `Rails.application.routes.draw do` block opened at the
# top of the file — every route declared above lives inside this block.
