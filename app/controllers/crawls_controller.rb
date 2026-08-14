# =============================================================================
# CRAWLS CONTROLLER
# =============================================================================
# Handles starting, viewing, and managing crawl runs.
# =============================================================================
# A "crawl" (see CrawlRun / CrawlJob elsewhere in the app) is a background
# job that visits self-storage company websites and collects current unit
# prices for a given city/radius. This controller is the web-facing layer
# that starts crawls and lets the user check on / manage them.

# `class CrawlsController < ApplicationController`, see
# app/controllers/application_controller.rb for what "controller" and
# "inherits from" mean in this codebase.
class CrawlsController < ApplicationController
  # ---------------------------------------------------------------------------
  # CREATE, start a new crawl (called when user clicks "Run Crawl")
  # ---------------------------------------------------------------------------
  # `create` is the conventional Rails action name for "start/save a new
  # thing" (POST /crawls), here, "starting a new crawl" rather than saving
  # a simple database record directly.
  def create
    # Refuse to start a new crawl if one is already running
    # `CrawlRun.any_running?` is a custom method on the CrawlRun model that
    # checks whether any crawl is currently mid-run, running two crawls
    # at once isn't supported.
    if CrawlRun.any_running?
      # `respond_to do |format| ... end` lets ONE action serve different
      # response types depending on what the caller asked for, a normal
      # browser page load (`format.html`) vs. a JavaScript/AJAX request
      # expecting JSON data back (`format.json`). `do |format| ... end` is
      # Ruby block syntax: `respond_to` is called with a block (a chunk of
      # code passed in to be run), and `|format|` names the one argument
      # that block receives, an object you call `.html { ... }` /
      # `.json { ... }` on to register what each response type should do.
      respond_to do |format|
        # `format.html { ... }` registers what to do for a normal
        # (non-AJAX) browser request. The `{ ... }` here is Ruby's curly-
        # brace block syntax (an alternative to `do...end`, more common for
        # short blocks written on fewer lines).
        format.html {
          # Sets a flash alert message (see AlertRulesController's
          # comments for what `flash` is) shown on the next page load.
          flash[:alert] = "A crawl is already running. Please wait for it to finish before starting a new one."
          # Sends the browser back to the dashboard/home page.
          redirect_to root_path
        }
        # `}` closes the `format.html { ... }` block above.
        # `format.json { ... }` registers what to do when the caller wants
        # JSON instead of an HTML redirect, used by JavaScript on the
        # dashboard that submits this form via AJAX instead of a full page
        # navigation. `render json: {...}` sends back a JSON body built
        # from the given Ruby hash; `status: :conflict` sets the HTTP
        # status code to 409 ("Conflict", the request couldn't be
        # completed because of the current state, i.e. a crawl already
        # running).
        format.json { render json: { error: "A crawl is already running" }, status: :conflict }
      end
      # `end` closes the `respond_to do |format| ... end` block above.
      # Exits the `create` method immediately, nothing below should run
      # once we've already responded that a crawl can't be started.
      return
    end
    # `end` closes the `if CrawlRun.any_running?` block opened above.

    # Validate that we have a search city
    # `params[:search_city]` reads the "search_city" field submitted by the
    # form. `&.` is Ruby's "safe navigation operator", it calls `.strip`
    # (which removes leading/trailing whitespace) ONLY if the value isn't
    # nil; if `params[:search_city]` is nil (field missing entirely), the
    # whole expression short-circuits to nil instead of raising an error
    # (nil has no `.strip` method).
    search_city = params[:search_city]&.strip
    # `.blank?` is a Rails helper true for nil, empty string "", or a
    # whitespace-only string, broader than just checking `.nil?`.
    if search_city.blank?
      # Same html/json dual-response pattern as above, this time reporting
      # a validation failure instead of "already running."
      respond_to do |format|
        format.html {
          flash[:alert] = "Please enter a city name or ZIP code to search."
          redirect_to root_path
        }
        # `status: :unprocessable_entity` is HTTP 422, "the request was
        # understood, but the data in it was invalid."
        format.json { render json: { error: "Search city is required" }, status: :unprocessable_entity }
      end
      return
    end
    # `end` closes the `if search_city.blank?` block above.

    # Validate the radius
    # `params[:radius_miles]` reads the submitted search-radius field;
    # `.to_i` converts it to an integer, returning 0 for anything
    # unparseable (missing, blank, or non-numeric text) rather than raising
    # an error.
    radius = params[:radius_miles].to_i
    # Rejects radii that are zero/negative (invalid or unparseable input)
    # or absurdly large (over 500 miles), `||` is "or": either condition
    # being true is enough to fail validation.
    if radius <= 0 || radius > 500
      respond_to do |format|
        format.html {
          flash[:alert] = "Radius must be between 1 and 500 miles."
          redirect_to root_path
        }
        format.json { render json: { error: "Invalid radius" }, status: :unprocessable_entity }
      end
      return
    end
    # `end` closes the `if radius <= 0 || radius > 500` block above.

    # Build filter options from form params.
    # sizes[] and companies[] are real checkbox arrays (see dashboard/index.html.erb),
    # not comma-separated strings.
    # `options = { ... }` builds a Ruby hash literal (curly braces, `key:
    # value` pairs) capturing every filter to pass along to the background
    # crawl job.
    options = {
      # `Array(params[:sizes])` wraps whatever `params[:sizes]` is into an
      # Array, if it's already an array (checkbox fields with `[]` in
      # their name arrive as arrays), it's returned as-is; if it's nil,
      # `Array(nil)` returns an empty array `[]` (instead of erroring or
      # leaving it nil), which is safer to chain `.presence` off of next.
      # `.presence` is a Rails helper that returns the array itself if it's
      # non-empty, or nil if it IS empty; `||` then falls back to
      # `Unit::DEFAULT_SIZES` (a constant defined on the Unit model) when
      # nothing was checked.
      sizes:             Array(params[:sizes]).presence || Unit::DEFAULT_SIZES,
      # The climate-controlled checkbox defaults to "on": this is true
      # UNLESS the submitted value is literally the string "false", so a
      # missing/absent param (as opposed to an explicit "false") still
      # counts as true.
      climate_controlled: params[:climate_only] != "false",
      # Same `Array(...).presence` pattern as sizes, an empty/absent
      # companies selection becomes nil (meaning "no company filter," i.e.
      # include all companies) rather than an empty array (which could be
      # misread as "match nothing").
      companies:         Array(params[:companies]).presence,
      # `Unit::EXCLUDED_TYPES` is a constant on the Unit model listing unit
      # types (e.g. parking, vehicle storage) that should never be crawled
      # for/shown, not user-configurable, so it's included as a fixed
      # value here rather than read from params.
      exclude_types:     Unit::EXCLUDED_TYPES
    }
    # `}` (the closing brace) ends the `options = { ... }` hash literal.

    # Create the CrawlRun record
    # `CrawlRun.create!(...)` builds AND saves a new database row in one
    # call. The `!` (bang) at the end of `create!` is a Ruby naming
    # convention (not special syntax) meaning "the dangerous/strict
    # version", unlike plain `.create`, which silently returns an invalid,
    # unsaved record on failure, `.create!` RAISES an error
    # (ActiveRecord::RecordInvalid) if validation fails, which is caught
    # by the `rescue` clause near the bottom of this method.
    crawl_run = CrawlRun.create!(
      search_city:          search_city,
      search_radius_miles:  radius,
      # Sets the initial status column to the string "pending", the
      # CrawlJob (enqueued below) will update this as it progresses.
      status:               "pending",
      filter_options:       options,
      # `options[:companies] || CompanyRegistry.all_company_names` records
      # exactly which companies this crawl covers: either the user's
      # explicit selection, or, if none was made, every company known to
      # CompanyRegistry (a registry/list of supported storage companies
      # elsewhere in the app), so the record always reflects the real set
      # searched even when the user didn't narrow it down.
      companies_included:   options[:companies] || CompanyRegistry.all_company_names
    )

    # Writes a log line recording that a new CrawlRun was created, including
    # its database ID (`crawl_run.id`), the city searched, and the radius,
    # useful when debugging via the server log.
    Rails.logger.info("[CrawlsController] Created CrawlRun ##{crawl_run.id} for '#{search_city}' within #{radius} miles")

    # Enqueue the background job, this returns immediately, job runs in background
    # `CrawlJob.perform_later(...)` schedules CrawlJob to run asynchronously
    # (outside of, and after, this web request) via Rails' ActiveJob
    # background-job system, the actual slow work of visiting websites
    # happens there, not in this controller, so the browser gets a fast
    # response instead of waiting minutes for the crawl to finish.
    CrawlJob.perform_later(crawl_run_id: crawl_run.id, options: options)

    Rails.logger.info("[CrawlsController] CrawlJob enqueued for CrawlRun ##{crawl_run.id}")

    # Final success response, again split html vs. json.
    respond_to do |format|
      format.html {
        flash[:notice] = "Crawl started for '#{search_city}' within #{radius} miles. Results will appear below as they come in."
        redirect_to root_path
      }
      format.json {
        # `render json: { ... }, status: :created` sends back a JSON body
        # describing the newly created crawl, with HTTP status 201
        # ("Created"), the conventional status code for successful
        # resource-creation requests.
        render json: {
          crawl_run_id: crawl_run.id,
          message:      "Crawl started",
          status:       "pending"
        }, status: :created
      }
    end
  # `end` closes the final `respond_to do |format| ... end` block above.

  # `rescue ActiveRecord::RecordInvalid => e` catches the specific error
  # `CrawlRun.create!` raises if validation fails (see comment above), and
  # binds the caught error object to the local variable `e` (`=>` here
  # means "and assign it to") so its details can be used below. Because
  # this `rescue` is written directly under `def create` (not nested inside
  # an inner `begin...end`), it applies to any matching error raised
  # ANYWHERE in the method body above it, this is Ruby's "method-level
  # rescue" shorthand.
  rescue ActiveRecord::RecordInvalid => e
    # The CrawlRun record failed validation, shouldn't happen with our checks above,
    # but handle it gracefully just in case
    # `e.message` reads the human-readable description of what went wrong,
    # logged here for debugging.
    Rails.logger.error("[CrawlsController] Failed to create CrawlRun: #{e.message}")
    respond_to do |format|
      format.html {
        flash[:alert] = "Could not start crawl: #{e.message}"
        redirect_to root_path
      }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end
  # `end` closes the `def create` action definition (the `rescue` clause
  # above is part of this same method).

  # ---------------------------------------------------------------------------
  # SHOW, detail page for one crawl run (shows log entries)
  # ---------------------------------------------------------------------------
  # `show` displays the detail page for one specific CrawlRun (GET
  # /crawls/:id), including its log entries.
  def show
    # Loads the specific CrawlRun by the `:id` URL segment, see
    # AlertRulesController#set_alert_rule for how `params[:id]` and
    # `.find` work together. `.find` raises ActiveRecord::RecordNotFound
    # if no matching row exists, caught by the `rescue` below.
    @crawl_run = CrawlRun.find(params[:id])
    # `.crawl_log_entries` is an ActiveRecord association, a method Rails
    # generates from the model's `has_many :crawl_log_entries` declaration
    # , returning every CrawlLogEntry row linked to this crawl.
    # `.order(:created_at)` sorts them oldest-first.
    @log_entries = @crawl_run.crawl_log_entries.order(:created_at)
    @page_title = "Crawl ##{@crawl_run.id}, StorageFinder"

  # Catches a lookup failure for an invalid/nonexistent crawl ID.
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Crawl run ##{params[:id]} not found."
    redirect_to root_path
  end
  # `end` closes the `def show` action definition (the `rescue` clause
  # above is part of this same method).

  # ---------------------------------------------------------------------------
  # LOG, JSON endpoint that returns log entries for a running crawl
  # Used by the live progress feed on the dashboard
  # ---------------------------------------------------------------------------
  # `log` is a custom (non-RESTful/non-conventional) action added to this
  # controller, it exists purely to serve JSON, polled repeatedly by the
  # dashboard's JavaScript while a crawl runs, to fetch newly-appeared log
  # lines. (Its route must be defined explicitly in config/routes.rb, unlike
  # index/show/create/update/destroy, which Rails wires up automatically for
  # a `resources` declaration.)
  def log
    # Loads the CrawlRun this log request is about. Note: unlike `show`
    # above, there's no local `rescue` around JUST this line, the method-
    # level `rescue` near the bottom covers the whole method body.
    crawl_run   = CrawlRun.find(params[:id])
    # Reads the `since_id` query parameter (e.g. ?since_id=42) and converts
    # it to an integer (0 if missing/invalid), the dashboard uses this to
    # ask "only give me log entries newer than the ones I already have,"
    # avoiding re-fetching/re-displaying the same lines on every poll.
    since_id    = params[:since_id].to_i  # Only return entries newer than this ID

    # `.where("id > ?", since_id)` is ActiveRecord's parameterized-query
    # syntax: the `?` is a placeholder safely substituted with `since_id`
    # (protecting against SQL injection, unlike directly interpolating
    # since_id into the string). `.order(:created_at)` sorts oldest-first
    # so new lines appear at the bottom, matching a normal log feed.
    entries = crawl_run.crawl_log_entries
                       .where("id > ?", since_id)
                       .order(:created_at)

    # Sends back a JSON object with the matching log entries (reshaped into
    # a plain array of small hashes) plus the crawl's overall status.
    render json: {
      # `entries.map { |e| { ... } }` builds a new array by transforming
      # each CrawlLogEntry database record (`e`) into a plain hash of just
      # the fields the frontend needs, `.map` runs the block once per
      # entry and collects each block's return value into a new array.
      entries: entries.map { |e|
        {
          id:        e.id,
          level:     e.level,
          company:   e.company,
          message:   e.message,
          # `.strftime("%H:%M:%S")` formats the entry's timestamp as
          # 24-hour hours:minutes:seconds (Ruby/Rails time-formatting
          # syntax, borrowed from C's strftime) for display in the log feed.
          timestamp: e.created_at.strftime("%H:%M:%S"),
          css_class: e.css_class
        }
      },
      # `}` closes the `entries.map { |e| ... }` block just above.
      crawl_status: crawl_run.status,
      # `.finished?` is a custom predicate method on CrawlRun (a "predicate"
      # is Ruby convention: a method ending in `?` that returns true/false)
      # telling the dashboard whether it should stop polling.
      finished:     crawl_run.finished?
    }
  # `}` closes the `render json: { ... }` hash argument.

  # Catches the case where `params[:id]` doesn't match any CrawlRun, since
  # this is a polled JSON endpoint, the response here is JSON (not a
  # redirect, which would make no sense for a background AJAX poll).
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Crawl run not found" }, status: :not_found
  end
  # `end` closes the `def log` action definition (the `rescue` clause above
  # is part of this same method).

  # ---------------------------------------------------------------------------
  # DESTROY, cancel a running crawl (marks it as failed), or permanently
  # delete the record (and its units/log entries) once it's finished
  # ---------------------------------------------------------------------------
  # `destroy` here does double duty: cancel an in-progress crawl, OR delete
  # a finished one's history record, the behavior depends on the record's
  # current state (see the `if crawl_run.finished?` branch below).
  def destroy
    crawl_run = CrawlRun.find(params[:id])

    # `.finished?` (see comment in `log` above) is true once a crawl has
    # completed or failed, i.e. it's no longer actively running.
    if crawl_run.finished?
      # Since the crawl is already done, "destroy" here means permanently
      # delete the historical record (and, via the model's association
      # configuration, its related units/log entries too, Rails handles
      # cascading deletes based on how the model's associations are set
      # up, which isn't shown in this controller file).
      crawl_run.destroy!

      respond_to do |format|
        format.html {
          flash[:notice] = "Crawl record deleted."
          redirect_to root_path
        }
        # No explicit `status:` here, `render json: {...}` on its own
        # defaults to HTTP 200 ("OK").
        format.json { render json: { message: "Crawl deleted" } }
      end
    else
      # The crawl is still running (or pending), deleting it out from
      # under an in-progress background job would be unsafe, so instead
      # this branch marks it as cancelled/failed rather than deleting the
      # row. `.fail!` is a custom model method transitioning the record's
      # status and recording the given reason string. `Time.current` is
      # Rails' timezone-aware "now" (preferred over plain Ruby `Time.now`,
      # which ignores the app's configured time zone);
      # `.strftime("%I:%M %p")` formats it as 12-hour time with AM/PM.
      crawl_run.fail!("Cancelled by user at #{Time.current.strftime("%I:%M %p")}")

      respond_to do |format|
        format.html {
          flash[:notice] = "Crawl cancelled."
          redirect_to root_path
        }
        format.json { render json: { message: "Crawl cancelled", status: "failed" } }
      end
    end
  # `end` closes the `if crawl_run.finished? ... else ... end` block above.

  # FIXED: this `rescue` used to always `render json: ...`, even for a
  # plain (non-AJAX) browser request, unlike the `if`/`else` branches
  # above it, which both split html vs. json via `respond_to`. Now matches
  # that same pattern, so a browser hitting a missing crawl ID gets a
  # redirect + flash message instead of a raw JSON body.
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html {
        flash[:alert] = "Crawl run not found."
        redirect_to root_path
      }
      format.json { render json: { error: "Crawl run not found" }, status: :not_found }
    end
  end
  # `end` closes the `def destroy` action definition (the `rescue` clause
  # above is part of this same method).

  # ---------------------------------------------------------------------------
  # DESTROY_SELECTED, bulk-delete crawl history records
  # Used by the "select all" / "Delete Selected" controls in the history panel.
  # Only finished crawls (completed/failed) are deleted, a still-running or
  # pending crawl is skipped rather than deleted out from under its job.
  # ---------------------------------------------------------------------------
  # `destroy_selected` is another custom action (needs an explicit route in
  # config/routes.rb) allowing multiple crawl records to be deleted in one
  # request, e.g. via checkboxes + a "Delete Selected" button.
  def destroy_selected
    # `params[:ids]` is expected to be an array of ID strings/numbers from
    # the submitted checkboxes. `Array(...)` guarantees an array even if
    # it's missing/nil (see the `create` action's comment on `Array(...)`
    # for why). `.map(&:to_i)` converts every element to an integer,
    # `&:to_i` is Ruby shorthand for `{ |x| x.to_i }`, turning the symbol
    # `:to_i` into a block that calls that method on each array element.
    # `.reject(&:zero?)` then drops any resulting 0s (from blank/invalid
    # entries), since 0 is never a real database ID.
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)

    # If nothing valid was selected, report that instead of proceeding.
    if ids.empty?
      respond_to do |format|
        format.html {
          flash[:alert] = "No crawl records were selected."
          redirect_to root_path
        }
        format.json { render json: { error: "No ids given" }, status: :unprocessable_entity }
      end
      return
    end
    # `end` closes the `if ids.empty?` block above.

    # `CrawlRun.where(id: ids)` fetches every CrawlRun whose id is IN the
    # given list, a single database query rather than looping and querying
    # once per ID.
    crawl_runs    = CrawlRun.where(id: ids)
    # `.select(&:finished?)` (Ruby's Array#select, filtering to elements
    # where the block returns true, here using the same `&:method_name`
    # shorthand as above) keeps only the crawl runs that are actually
    # finished; `.map(&:id)` then reduces those kept records down to just
    # their IDs, since that's all the deletion step below needs.
    deletable_ids = crawl_runs.select(&:finished?).map(&:id)
    # The remainder, selected but not yet finished, are the ones being
    # silently skipped; this count is used to tell the user about them.
    skipped_count = crawl_runs.size - deletable_ids.size

    deleted_count = deletable_ids.size
    # `.destroy_all` on a `.where(...)` scope loads and destroys every
    # matching record (running each one's callbacks/associations), as
    # opposed to `.delete_all`, which would skip callbacks for speed, this
    # matters if CrawlRun has associated units/log entries that need
    # cleanup logic on delete.
    CrawlRun.where(id: deletable_ids).destroy_all

    # Builds a human-readable summary message. `"s" unless deleted_count ==
    # 1` is a Ruby trick: `unless` as a trailing modifier means "unless the
    # condition after it is true", so this evaluates to the string "s"
    # normally, but to `nil` (which prints as nothing when interpolated)
    # when deleted_count is exactly 1, giving correct singular/plural
    # grammar ("1 crawl record." vs "2 crawl records.").
    message = "Deleted #{deleted_count} crawl record#{"s" unless deleted_count == 1}."
    # If any selected records were skipped (still running), append a note
    # about them.
    if skipped_count > 0
      # Same singular/plural trick as above, plus a ternary
      # (`condition ? if_true : if_false`) choosing "it" vs. "them"
      # depending on whether exactly one record was skipped.
      message += " Skipped #{skipped_count} still-running crawl#{"s" unless skipped_count == 1}, cancel #{skipped_count == 1 ? "it" : "them"} first to delete."
    end
    # `end` closes the `if skipped_count > 0` block above.

    respond_to do |format|
      format.html {
        flash[:notice] = message
        redirect_to root_path
      }
      format.json { render json: { message: message, deleted: deleted_count, skipped: skipped_count } }
    end
  end
  # `end` closes the `def destroy_selected` action definition opened above.
end
# `end` closes the `class CrawlsController` definition opened at the top of
# the file.
