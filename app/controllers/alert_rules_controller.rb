# =============================================================================
# ALERT RULES CONTROLLER
# =============================================================================
# CRUD for alert rules — create, view, edit, delete price alert rules.
# =============================================================================
# "CRUD" is a common shorthand for the four basic data operations every
# resource typically needs: Create, Read, Update, Delete. This controller
# implements all four for AlertRule records (each one is a rule like "email
# me when a 10x10 unit drops below $80/month").

# `class AlertRulesController < ApplicationController` makes this controller
# inherit from (be built on top of) ApplicationController (see
# app/controllers/application_controller.rb), which in turn is built on
# Rails' own controller base class. Every method Rails routes to (an
# "action") is just a normal public Ruby method defined inside this class.
class AlertRulesController < ApplicationController
  # `before_action` registers a method to run automatically BEFORE certain
  # actions, without having to call it manually inside each one. The first
  # argument, `:set_alert_rule` (a Ruby symbol — a lightweight name/label),
  # names the private method defined further down to run. `only: [...]` is a
  # keyword argument restricting it to just the four listed actions (an
  # Array literal, written with square brackets and comma-separated
  # symbols) — it will NOT run before `index`, `new`, or `create`, since
  # those don't need an existing record loaded.
  before_action :set_alert_rule, only: [ :show, :edit, :update, :destroy ]

  # `index` is the conventional Rails action name for "list all records of
  # this type" — it's what runs when a browser requests the alert rules
  # listing page (GET /alert_rules).
  def index
    # `AlertRule.all` asks the database for every row in the alert_rules
    # table; `.order(:name)` sorts those results alphabetically by the
    # `name` column. The result is stored in `@alert_rules`, an instance
    # variable — this makes it automatically available to the view template
    # that Rails renders after this action finishes (views can read
    # instance variables set by the controller action, but not local/plain
    # variables).
    @alert_rules = AlertRule.all.order(:name)
    # Sets the page's browser-tab title, read later by
    # ApplicationController#current_page_title (see application_controller.rb).
    @page_title  = "Alert Rules — StorageFinder"
  end
  # `end` closes the `def index` action definition opened above.

  # `show` is the conventional action name for "display one specific
  # record's details page" (GET /alert_rules/:id). Because `:show` is
  # listed in the `before_action` above, `set_alert_rule` has already run
  # and populated `@alert_rule` by the time this method's body executes.
  def show
    # Builds the page title using the already-loaded record's name.
    # `"#{...}"` is Ruby string interpolation — it evaluates the Ruby
    # expression inside `#{}` and inserts its result into the surrounding
    # string.
    @page_title = "#{@alert_rule.name} — StorageFinder"
  end
  # `end` closes the `def show` action definition opened above.

  # `new` is the conventional action for "show a blank form to create a
  # record" (GET /alert_rules/new). Unlike show/edit/update/destroy, `new`
  # is NOT in the before_action list, because there's no existing record to
  # load yet — this action builds a brand new, unsaved one instead.
  def new
    # `AlertRule.new` builds a new AlertRule object in memory ONLY — it does
    # NOT save anything to the database yet. This lets the form view
    # reference `@alert_rule.name`, `@alert_rule.trigger_type`, etc., for
    # blank input fields without erroring on a missing record.
    @alert_rule = AlertRule.new
    @page_title = "New Alert Rule — StorageFinder"
  end
  # `end` closes the `def new` action definition opened above.

  # `create` is the conventional action that actually saves a new record
  # (POST /alert_rules) — this is what runs when the "new alert rule" form
  # from the `new` action above gets submitted.
  def create
    # Builds a new, unsaved AlertRule using only the specific fields
    # whitelisted by `alert_rule_params` below (never raw, unfiltered
    # `params` — see that method's comments for why).
    @alert_rule = AlertRule.new(alert_rule_params)

    # `.save` attempts to write the record to the database and returns
    # true if it succeeded (passed all model validations) or false if it
    # failed (e.g. a required field was blank). `if` branches on that
    # true/false result.
    if @alert_rule.save
      # `flash` is Rails' mechanism for a one-time message that survives
      # exactly one redirect, then disappears — perfect for "success!"
      # banners after a form submission. `flash[:notice]` sets it under the
      # `:notice` key, which the layout template renders as a positive/info
      # style message.
      flash[:notice] = "Alert rule '#{@alert_rule.name}' created."
      # `redirect_to` tells the browser to make a brand-new GET request to
      # a different URL (here, the alert rules listing page) — this is
      # different from `render` (used in the `else` branch below), which
      # sends back a page directly without a second round-trip to the
      # browser. `alert_rules_path` is a Rails-generated helper method that
      # returns the URL string for the alert rules index (defined via
      # config/routes.rb).
      redirect_to alert_rules_path
    else
      # Save failed — build an error message so the re-rendered form can
      # show what went wrong. `flash.now[:alert]` differs from plain
      # `flash[:alert]`: `.now` makes the message available ONLY for the
      # page rendered in THIS same request/response cycle (via `render`
      # just below), not carried over to a future request the way
      # `redirect_to`-paired flash messages are — appropriate here since
      # we're NOT redirecting.
      # `@alert_rule.errors.full_messages` returns an array of human-
      # readable validation error strings (e.g. "Name can't be blank");
      # `.join(", ")` concatenates that array into one comma-separated
      # string for display.
      flash.now[:alert] = "Could not create alert rule: #{@alert_rule.errors.full_messages.join(", ")}"
      # `render :new` re-displays the SAME "new alert rule" form template
      # (rather than redirecting to a different URL) so the user's
      # already-entered values (still held in the in-memory `@alert_rule`
      # object) and the error message are shown together. `status:
      # :unprocessable_entity` sets the HTTP response status code to 422,
      # the conventional code meaning "the request was well-formed but
      # failed validation" — this matters for JavaScript/browsers that
      # check the status code to know a submission failed.
      render :new, status: :unprocessable_entity
    end
    # `end` closes the `if @alert_rule.save` / `else` block above.
  end
  # `end` closes the `def create` action definition opened above.

  # `edit` shows a pre-filled form for changing an existing record (GET
  # /alert_rules/:id/edit). `set_alert_rule` (via before_action) has
  # already loaded `@alert_rule` by this point.
  def edit
    @page_title = "Edit #{@alert_rule.name} — StorageFinder"
  end
  # `end` closes the `def edit` action definition opened above.

  # `update` saves changes to an existing record (PATCH/PUT
  # /alert_rules/:id) — submitted from the `edit` form above.
  def update
    # `.update(...)` on an ALREADY-LOADED record (unlike `.save` on a brand
    # new one in `create`) both assigns the given attributes AND saves them
    # in one step, returning true/false the same way `.save` does.
    if @alert_rule.update(alert_rule_params)
      flash[:notice] = "Alert rule updated."
      redirect_to alert_rules_path
    else
      # Same pattern as the `create` action's failure branch above: use
      # `flash.now` (this-request-only) and re-render the form, this time
      # `:edit`, with the validation errors.
      flash.now[:alert] = "Could not update: #{@alert_rule.errors.full_messages.join(", ")}"
      render :edit, status: :unprocessable_entity
    end
    # `end` closes the `if @alert_rule.update(...)` / `else` block above.
  end
  # `end` closes the `def update` action definition opened above.

  # `destroy` permanently deletes an existing record (DELETE
  # /alert_rules/:id).
  def destroy
    # Captures the name BEFORE deleting the record, since after
    # `.destroy` the record (and thus `.name`) would no longer be safely
    # readable/relevant for the flash message below.
    name = @alert_rule.name
    # `.destroy` deletes this record's row from the database.
    @alert_rule.destroy
    flash[:notice] = "Alert rule '#{name}' deleted."
    redirect_to alert_rules_path
  end
  # `end` closes the `def destroy` action definition opened above.

  # `private` marks every method below as internal to this class — not
  # directly reachable as a URL/action, and not callable from outside this
  # controller. `set_alert_rule` and `alert_rule_params` below are
  # implementation details supporting the public actions above them.
  private

  # This is the method wired up by `before_action :set_alert_rule` at the
  # top of the file — it runs automatically before show/edit/update/destroy
  # to load the specific record those actions operate on.
  def set_alert_rule
    # `params` is a hash-like object Rails builds from the incoming
    # request's URL segments, query string, and form/JSON body.
    # `params[:id]` reads the `:id` segment (e.g. the "5" in
    # /alert_rules/5) — Rails' routes wire up `:id` as part of the URL
    # pattern for these RESTful routes. `AlertRule.find(...)` looks up the
    # single database row with that primary key, raising an error
    # (ActiveRecord::RecordNotFound) if no such row exists.
    @alert_rule = AlertRule.find(params[:id])
  # `rescue` catches an error raised anywhere in the method body above it
  # (here, specifically an `ActiveRecord::RecordNotFound`, listed to avoid
  # accidentally swallowing unrelated bugs) and runs this block instead of
  # letting the error crash the request.
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Alert rule not found."
    redirect_to alert_rules_path
  end
  # `end` closes the `def set_alert_rule` method definition (the `rescue`
  # clause above is part of the same method, not a separate block).

  # Defines the whitelist of form fields allowed to be mass-assigned into an
  # AlertRule when creating/updating one — used by both `create` and
  # `update` above. This is Rails' "strong parameters" pattern: it exists so
  # a malicious or malformed request can't sneak in extra fields (e.g. an
  # `:id` or some other column) that the form was never meant to submit.
  def alert_rule_params
    # `params.require(:alert_rule)` asserts the incoming params MUST
    # contain a top-level `:alert_rule` key (matching how Rails form
    # helpers nest fields, e.g. `alert_rule[name]`) — raising an error if
    # it's missing, since something is badly wrong with the request if it's
    # not there. `.permit(...)` then filters that nested hash down to ONLY
    # the explicitly listed field names, silently dropping anything else —
    # each symbol below names one allowed field/database column.
    params.require(:alert_rule).permit(
      :name, :trigger_type, :threshold_price,
      :unit_size_filter, :company_filter,
      :email_enabled, :email_address,
      :discord_enabled, :discord_webhook_url,
      :sms_enabled, :sms_phone_number,
      :active, :cooldown_minutes
    )
    # The multi-line list above is one single method call to `.permit`,
    # split across lines for readability — Ruby doesn't require each
    # argument on its own line, but allows it.
  end
  # `end` closes the `def alert_rule_params` method definition opened above.
end
# `end` closes the `class AlertRulesController` definition opened at the top
# of the file.
