# =============================================================================
# ALERT CHECKER JOB
# =============================================================================
# Runs after every crawl to check if any alert rules have been triggered.
# Compares current prices to previous crawl prices and fires notifications.
# =============================================================================

# `class AlertCheckerJob < ApplicationJob` defines this class as an ActiveJob
# background job (see app/jobs/application_job.rb for what ActiveJob is and
# why jobs inherit from ApplicationJob). Being a job means this class can be
# scheduled to run outside of a normal web request, here, it's enqueued at
# the end of a crawl (see CrawlJob) via `AlertCheckerJob.perform_later(...)`.
# `perform_later` hands the work off to run asynchronously (whenever a
# background worker is free to pick it up), as opposed to `perform_now`
# which would run it immediately, blocking whatever called it.
class AlertCheckerJob < ApplicationJob
  # `queue_as :alerts` is an ActiveJob class method that assigns this job
  # to a named queue called "alerts" (`:alerts` is a Ruby SYMBOL, a
  # lightweight, immutable, named value often used as an identifier/label,
  # distinct from a String like "alerts" even though it looks similar).
  # Naming queues lets the app process different kinds of jobs with
  # different priority/worker settings if needed.
  queue_as :alerts

  # `def perform(crawl_run_id:)` defines the method ActiveJob actually
  # calls to run the job. This is a required convention: every ActiveJob
  # subclass must define `perform`. `crawl_run_id:` is a required keyword
  # argument, whoever enqueues this job (see CrawlJob) MUST call it as
  # `AlertCheckerJob.perform_later(crawl_run_id: some_id)`.
  def perform(crawl_run_id:)
    # `CrawlRun.find(crawl_run_id)` looks up the CrawlRun database row with
    # this ID. `.find` (as opposed to `.find_by`) raises
    # ActiveRecord::RecordNotFound if no matching row exists, rather than
    # quietly returning nil, that's intentional here, so a bad/deleted ID
    # fails loudly instead of causing confusing errors further down.
    current_run  = CrawlRun.find(crawl_run_id)
    # `AlertRule.active` calls a scope (a reusable, named database query)
    # defined on the AlertRule model that returns only the alert rules
    # currently marked as enabled/active.
    active_rules = AlertRule.active

    # `.empty?` checks whether the active_rules collection has zero
    # records. If there's nothing to check, there's no point doing any
    # more work, log and stop.
    if active_rules.empty?
      # `Rails.logger.info(...)` writes a line to the application's log
      # file/output at the "info" severity level, useful for later
      # debugging/auditing without interrupting anything.
      Rails.logger.info("[AlertCheckerJob] No active alert rules, skipping")
      # `return` immediately exits the `perform` method here, skipping
      # everything below it for this job run.
      return
    end
    # `end` closes the `if active_rules.empty?` block above.

    # Get the previous completed crawl run (the one before this one)
    #
    # This builds a database query in pieces (method chaining) to find the
    # most recent CrawlRun that finished successfully BEFORE this one, so
    # we can compare "current prices" to "previous prices."
    previous_run = CrawlRun.completed
                           # `.completed`, another named scope, filtering
                           # to only crawl runs whose status is "completed."
                           .where("id < ?", current_run.id)
                           # `.where("id < ?", current_run.id)` adds a SQL
                           # condition: only rows whose id is less than the
                           # current run's id (i.e., crawl runs that
                           # happened earlier). The `?` is a placeholder
                           # that Rails safely substitutes with
                           # current_run.id, preventing SQL injection.
                           .order(id: :desc)
                           # `.order(id: :desc)` sorts the matching rows by
                           # id, descending (highest/most recent id first).
                           .first
    # `.first` runs the query and returns just the
    # first result, i.e., the most recent completed
    # run before this one, or `nil` if there isn't
    # one (e.g. this is the very first crawl ever).

    Rails.logger.info(
      "[AlertCheckerJob] Checking #{active_rules.count} alert rules. " \
      "Previous crawl: #{previous_run ? "##{previous_run.id}" : "none (first crawl)"}"
      # `previous_run ? "##{previous_run.id}" : "none (first crawl)"` is a
      # ternary conditional (`condition ? value_if_true : value_if_false`)
      #, shorthand for a full if/else, used here inline inside the string
      # interpolation to describe the previous run or say there wasn't one.
    )

    # For each active alert rule, check each unit from the current crawl
    #
    # `.each do |rule| ... end` iterates over every record in
    # active_rules, running the block once per rule, with `rule` bound to
    # the current one each time.
    active_rules.each do |rule|
      # `begin ... rescue ... end` here is Ruby's exception-handling block:
      # code inside `begin` runs normally, but if it raises any error, the
      # matching `rescue` clause catches it instead of letting it crash
      # the loop (and the whole job) for every other rule too.
      begin
        # Runs the actual per-rule checking logic (defined below).
        check_rule(rule, current_run, previous_run)
      rescue => e
        # `rescue => e` with no error class listed catches any
        # StandardError (Ruby's normal, "expected to be catchable"
        # exception hierarchy) and stores it in local variable `e`.
        Rails.logger.error(
          "[AlertCheckerJob] Error checking rule '#{rule.name}': #{e.class}: #{e.message}"
        )
        # No `raise` here, the error is swallowed after logging, which is
        # deliberate: one broken alert rule shouldn't stop the other rules
        # from being checked.
      end
      # `end` closes the `begin/rescue` block for this iteration.
    end
    # `end` closes the `active_rules.each do |rule|` loop above.
  end
  # `end` closes the `def perform` method definition above.

  # `private` is a Ruby keyword that marks every method defined below it
  # (within this class) as callable only from inside this class's own
  # instance methods, not from outside code. It documents "these are
  # implementation details, not part of this job's public interface."
  private

  def check_rule(rule, current_run, previous_run)
    # Skip entirely if this rule is still within its own "quiet hours"
    # cooldown window (see AlertRule#in_cooldown?, configured via the
    # rule's cooldown_minutes field). Without this check, a rule like
    # "price below $100" would re-send an identical alert after EVERY
    # crawl for as long as the price stayed under $100, not just once when
    # it first dropped below, this early return is what stops that.
    if rule.in_cooldown?
      Rails.logger.info(
        "[AlertCheckerJob] Rule '#{rule.name}' is in cooldown until " \
        "#{(rule.last_triggered_at + rule.cooldown_minutes.minutes).strftime("%b %d at %I:%M %p")}, skipping"
      )
      return
    end
    # `end` closes the `if rule.in_cooldown?` block above.

    # Get all units from the current crawl that could match this rule
    #
    # `current_run.units` is an ActiveRecord association, it loads (or
    # prepares to load) all Unit records linked to this CrawlRun.
    # `.includes(:facility)` is Rails' "eager loading": it tells
    # ActiveRecord to fetch each unit's related Facility record in one
    # extra efficient batch query up front, instead of running a separate
    # database query every time `.facility` is called on each unit later
    # (which would otherwise cause a slow "N+1 queries" problem).
    current_units = current_run.units.includes(:facility)
    # If this rule only cares about a specific unit size (e.g. "10x10"),
    # narrow the query further. `.present?` (a Rails helper) is true when
    # the value isn't nil and isn't an empty string, i.e., a real filter
    # was actually configured on this rule.
    current_units = current_units.where(size: rule.unit_size_filter) if rule.unit_size_filter.present?
    # The trailing `if ...` here is Ruby's "modifier if", a compact way
    # of writing a one-line conditional, equivalent to wrapping the
    # statement in a full `if ... end` block.

    # For price_drop alerts, batch-load every previous-run unit's price up
    # front, keyed by [facility_id, size], one query total instead of one
    # query per current unit (previous_run.units.where(...).first for each).
    #
    # `previous_prices = {}` creates a new, empty Ruby Hash that will map
    # a [facility_id, size] pair to a previously recorded price.
    previous_prices = {}
    # Only bother building this lookup table if the rule actually needs
    # price-drop comparisons AND there was a previous run to compare
    # against (on the very first crawl ever, previous_run is nil).
    if rule.trigger_type == "price_drop" && previous_run
      # `previous_run.units.select(:id, :facility_id, :size,
      # :monthly_price, :web_special_price)`, `.select` limits which
      # database columns are actually fetched (a minor performance
      # optimization: we only need these five columns, not every column
      # on the units table). `.find_each` is an ActiveRecord method that
      # loads and yields records in batches internally (rather than
      # loading the entire table into memory at once), which matters if
      # there are a lot of unit rows, the block below still runs once per
      # record, exactly like `.each` would, just more memory-efficiently.
      previous_run.units.select(:id, :facility_id, :size, :monthly_price, :web_special_price).find_each do |prev_unit|
        # `key = [ prev_unit.facility_id, prev_unit.size ]` builds a
        # two-element Ruby Array to use as a composite hash key, Ruby
        # arrays can be used as hash keys (as long as their contents don't
        # change), which is handy here since we want to look things up by
        # the COMBINATION of facility and size, not just one or the other.
        key = [ prev_unit.facility_id, prev_unit.size ]
        # `previous_prices[key] ||= prev_unit.best_price` is Ruby's
        # "or-assign" operator: it only sets previous_prices[key] if it
        # isn't already set (i.e., if it's currently nil/falsy). This
        # preserves "first match wins" behavior if multiple previous units
        # share the same facility+size, matching what the original code
        # (a `.first` on a filtered query) used to do, per the comment.
        previous_prices[key] ||= prev_unit.best_price  # first match wins, same as the old .first
      end
      # `end` closes the `.find_each do |prev_unit|` block above.
    end
    # `end` closes the `if rule.trigger_type == "price_drop" && previous_run` block.

    # `triggered_units = []` starts a new empty array that will collect
    # every current unit (plus its previous price, if any) that actually
    # matches this rule's trigger conditions.
    triggered_units = []

    # Loop over every unit found in the current crawl that's eligible for
    # this rule (already filtered by size above, if applicable).
    current_units.each do |unit|
      # Look up whatever price was recorded for this exact facility+size
      # combination in the previous crawl, if any. `nil` if there wasn't
      # one (new unit, or no previous crawl).
      previous_price = previous_prices[[ unit.facility_id, unit.size ]]

      # `rule.matches_unit?` is a method on the AlertRule model that
      # contains the actual trigger logic (e.g. "did the price drop?" or
      # "is the price below the threshold?"), kept on the model since
      # it's about interpreting a single rule's own configuration.
      if rule.matches_unit?(unit, previous_price: previous_price)
        # `triggered_units << { unit: unit, previous_price: previous_price }`
        # appends (`<<` is Ruby's "append to array" operator) a new Hash
        # literal onto the triggered_units array, pairing the matching
        # unit with whatever previous price we compared it against (so
        # later code, like the message builder, can show "was $X, now
        # $Y" without re-querying).
        triggered_units << { unit: unit, previous_price: previous_price }
      end
      # `end` closes the `if rule.matches_unit?` check above.
    end
    # `end` closes the `current_units.each do |unit|` loop above.

    # `.any?` returns true if the array has at least one element, i.e.,
    # something actually matched this rule.
    if triggered_units.any?
      Rails.logger.info(
        "[AlertCheckerJob] Rule '#{rule.name}' triggered for #{triggered_units.length} units, sending alerts"
      )
      # Delegate to the private method below to build and send the actual
      # notification(s).
      send_alerts(rule, triggered_units)
      # `rule.record_triggered!`, a model method (the `!` at the end is a
      # Ruby/Rails naming convention meaning "this method has a
      # significant/dangerous side effect," here: it saves to the
      # database) that presumably updates bookkeeping like "last triggered
      # at" timestamps on the rule.
      rule.record_triggered!
    end
    # `end` closes the `if triggered_units.any?` block above.
  end
  # `end` closes the `def check_rule` method definition above.

  def send_alerts(rule, triggered_units)
    # Build the alert message
    #
    # `AlertMessageBuilder.build(...)` calls a class method on another
    # service object (see app/services/alerting/alert_message_builder.rb)
    # that assembles the actual subject/body text for the notification
    # from the rule and the list of triggered units.
    message = AlertMessageBuilder.build(rule, triggered_units)

    # Send via each enabled delivery method
    #
    # `AlertDeliveryService.deliver(...)` hands the built message off to
    # yet another service object (see
    # app/services/alerting/alert_delivery_service.rb) that's responsible
    # for actually sending it out (email, Discord, etc.) based on which
    # delivery channels are configured/enabled.
    AlertDeliveryService.deliver(rule, message)
  end
  # `end` closes the `def send_alerts` method definition above.
end
# `end` closes the `class AlertCheckerJob` definition that started at the
# top of this file.
