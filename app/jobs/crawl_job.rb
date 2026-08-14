# =============================================================================
# CRAWL JOB
# =============================================================================
# This is the background job that runs the actual crawl.
# It is enqueued by the DashboardController when the user clicks "Run Crawl."
# It runs in the background via ActiveJob's async adapter so the user's browser doesn't hang.
#
# What it does (in order):
#   1. Creates a CrawlRun record to track this session
#   2. Geocodes the search city to lat/lng coordinates
#   3. Launches a Playwright browser
#   4. Runs each company parser in sequence (or in parallel, based on settings)
#   5. Saves all results to the database
#   6. Calculates distances from the search origin
#   7. Checks alert rules and fires any alerts that are triggered
#   8. Broadcasts live progress to the dashboard via ActionCable
#   9. Marks the crawl as complete (or failed if something went wrong)
#
# REFACTORING NOTE: `perform` below used to be a single ~700-line method
# containing all 8 numbered steps inline, every other file in this app
# uses small, single-purpose private methods (see e.g.
# app/services/company_registry.rb), and a spot-check comment/refactor audit
# flagged this method as the one real outlier in that regard. It's been
# split into one private method per STEP (plus two further splits inside
# STEP 4, since the thread-pool orchestration and the per-company crawl
# logic are each substantial enough to deserve their own method), `perform`
# itself is now a short, readable sequence of calls that reads almost
# exactly like the numbered list above. No behavior changed in this split:
# every private method below does EXACTLY what its corresponding inline
# block used to do, just callable and readable on its own.
# =============================================================================

# This file is the largest and most complex one in the app, so before diving
# into line-by-line comments, here are the big Ruby/Rails concepts used
# throughout that a newcomer to Ruby wouldn't already know:
#
# ACTIVEJOB / BACKGROUND JOBS: A "job" is a chunk of work Rails can run
# OUTSIDE of a normal web request, e.g. triggered by a button click, then
# executed separately so the user's browser isn't stuck waiting. See
# app/jobs/application_job.rb for more on this. `perform_later(...)` (used
# elsewhere in this app to start this job) QUEUES the job to run soon,
# without blocking; `perform_now(...)` would run it immediately and
# synchronously instead. ActiveJob calls this class's `perform` method to
# actually execute the job.
#
# THREADS: Normally, Ruby code runs one instruction at a time, top to
# bottom, in a single "thread" of execution. A `Thread` is a way to run a
# SECOND (or third, fourth...) independent stream of code AT THE SAME TIME
# as the rest of your program, e.g. so this job can crawl 2+ storage
# companies' websites simultaneously instead of one after another, cutting
# total crawl time. `Thread.new do ... end` starts a new thread running the
# code in the block; the calling code continues immediately without waiting
# for that thread to finish. `some_thread.join` makes the CURRENT thread
# pause and wait until `some_thread` finishes.
#
# MUTEX (MUTUAL EXCLUSION LOCK): When multiple threads run at the same
# time, if two of them try to read-and-update the SAME shared piece of data
# at the exact same moment, the update can get corrupted (a "race
# condition"), e.g. two threads both read a counter as 5, both add 1, and
# both write back 6, when the correct final value should have been 7. A
# `Mutex` is a lock that only one thread can be holding at a time.
# `mutex.synchronize do ... end` says "wait until no other thread is inside
# a synchronize block on this same mutex, then run this code exclusively,
# then release the lock for the next thread waiting."
#
# TIMEOUT: `Timeout.timeout(seconds) do ... end` (from Ruby's standard
# library, loaded via `require "timeout"` below) runs the given block, but
# if it hasn't finished within `seconds` seconds, Ruby forcibly interrupts
# it by raising an exception inside that code, used here so one slow
# website can't stall the whole crawl indefinitely.
# =============================================================================

# `require "timeout"` loads Ruby's standard-library Timeout module into
# this file so `Timeout.timeout(...)` (used further down) is available.
# Unlike most Rails app code (which is auto-loaded by Zeitwerk without
# needing `require`), Ruby's standard library still needs to be explicitly
# required before use.
require "timeout"

# `class CrawlJob < ApplicationJob`, this job inherits from ApplicationJob
# (see app/jobs/application_job.rb), picking up its shared retry
# configuration automatically.
class CrawlJob < ApplicationJob
  # Raised when a single company's crawl (or the crawl as a whole) blows past
  # its time budget. Caught internally, it never bubbles up to ActiveJob, so it
  # does not trigger the retry_on StandardError below.
  #
  # `class CompanyTimeoutError < StandardError; end` defines a brand new,
  # custom exception TYPE, nested inside CrawlJob (accessed elsewhere as
  # `CrawlJob::CompanyTimeoutError`). It inherits from StandardError, Ruby's
  # normal base class for "ordinary," catchable errors. Defining a
  # dedicated error class (instead of reusing a generic one) lets the code
  # below `rescue CompanyTimeoutError` specifically, distinguishing "this
  # company timed out" from any other kind of failure. The `; end` on the
  # same line is just a compact one-line way of writing an otherwise-empty
  # class body, equivalent to writing `class CompanyTimeoutError <
  # StandardError` then `end` on the next line.
  class CompanyTimeoutError < StandardError; end

  # Use the "crawl" queue, ActiveJob's async adapter will process jobs from this queue
  #
  # Assigns this job to the queue named "crawl" (see AlertCheckerJob for
  # the same pattern with a different queue name), `:crawl` is a Ruby
  # symbol used here as the queue's identifier.
  queue_as :crawl

  # Retry configuration:
  # If the job crashes unexpectedly (NOT a per-company error, those are caught internally),
  # retry up to 2 times with exponential backoff (5 min, 25 min)
  #
  # `retry_on StandardError, attempts: 2, wait: :polynomially_longer`, if
  # `perform` (below) raises ANY StandardError that escapes all the way out
  # (i.e. wasn't caught somewhere inside), ActiveJob will automatically
  # re-run the whole job, up to 2 total attempts, waiting increasingly
  # longer between each retry. Per-company errors are deliberately caught
  # INSIDE `perform` (see the per-company rescue blocks further down) so
  # they never reach this outer retry mechanism, only a truly unexpected,
  # job-level failure would trigger a full retry here.
  retry_on StandardError, attempts: 2, wait: :polynomially_longer

  # Don't retry Playwright installation errors, those need manual intervention.
  # Instead of silently discarding, rescue and mark the crawl as failed so the
  # user can see what went wrong on the dashboard.
  rescue_from Playwright::Error do |error|
    if @crawl_run
      @crawl_run.fail!("Playwright error: #{error.message}")
      if @crawl_run.facility_ids&.any?
        @crawl_run.update_column(:completed_at, Time.current)
      end
    end
  end

  # Hard cap on how long a single company's parser.run can take. Sites vary a
  # lot in how many locations they have and how slow their pages load, this
  # exists so one bad/slow company can't sit there forever instead of moving
  # on to the next one.
  #
  # A plain Ruby constant (capitalized name) holding an Integer, number of
  # seconds. `# 2 minutes` is an inline trailing comment clarifying the
  # units in human terms.
  COMPANY_TIMEOUT_SECONDS = 120 # 2 minutes

  # Hard cap on the whole crawl (all companies combined). Once this elapses,
  # worker threads stop picking up new companies, whatever hasn't run yet is
  # skipped and logged rather than left to run indefinitely.
  CRAWL_TIMEOUT_SECONDS = 300 # 5 minutes

  # ---------------------------------------------------------------------------
  # PERFORM
  # ---------------------------------------------------------------------------
  # This is the method ActiveJob calls to run the job.
  # Arguments come from CrawlJob.perform_later(crawl_run_id: ..., options: ...)
  # ---------------------------------------------------------------------------
  #
  # `crawl_run_id:` is a required keyword argument; `options: {}` is an
  # optional keyword argument defaulting to an empty Hash if the caller
  # doesn't supply one.
  def perform(crawl_run_id:, options: {})
    # Fetch the CrawlRun record from the database
    # Use find! so we get a clear error if the ID doesn't exist
    #
    # `.find` raises ActiveRecord::RecordNotFound if no row with this ID
    # exists, that's handled by the `rescue ActiveRecord::RecordNotFound`
    # clause near the bottom of this method.
    @crawl_run = CrawlRun.find(crawl_run_id)
    crawl_run = @crawl_run

    # Double-check it's not already running (in case of race condition)
    #
    # `crawl_run.running?` is presumably a model method checking the
    # record's status column. This guards against the (unlikely but
    # possible) scenario where two workers somehow both picked up a job for
    # the same crawl run, the second one to get here bails out instead of
    # duplicating work.
    if crawl_run.running?
      Rails.logger.warn("[CrawlJob] CrawlRun ##{crawl_run_id} is already running, aborting duplicate job")
      return
    end
    # `end` closes the `if crawl_run.running?` block above.

    # Mark the crawl as started
    #
    # `crawl_run.start!`, a model method (again, `!` signals a meaningful
    # side effect: this saves a status change to the database) that flips
    # the record's status to "running" and likely records a start
    # timestamp.
    crawl_run.start!
    # Sends a live update to the dashboard (see the broadcast_status
    # private method near the bottom of this file) so the user immediately
    # sees the crawl has begun.
    broadcast_status(crawl_run, "Crawl started, geocoding search location...")

    # STEP 1: Geocode the search city to lat/lng, see geocode_search_location
    # below. Returns `[search_lat, search_lng]` on success, or `nil` if
    # geocoding failed, in which case geocode_search_location has already
    # marked the crawl_run failed and broadcast the error itself, so there's
    # nothing left to do here except stop.
    coordinates = geocode_search_location(crawl_run)
    return if coordinates.nil?

    search_lat, search_lng = coordinates
    # `||` fallback: use the crawl run's configured radius, or default to
    # 100 (miles) if none was set (nil).
    radius_miles = crawl_run.search_radius_miles || 100

    # STEP 2: Determine which companies to crawl, see
    # resolve_companies_to_crawl below.
    companies_to_crawl = resolve_companies_to_crawl(crawl_run, options)

    # STEPS 3-5: Launch Playwright, run every company's parser (in parallel,
    # up to the configured thread-pool size), then calculate distances once
    # all companies are done, see crawl_companies_and_calculate_distances
    # below. Returns `{ facilities: N, units: N }` totals on success, or
    # `nil` if the Playwright CLI couldn't be found at all, in which case
    # that method has already marked the crawl_run failed and broadcast the
    # error itself, so there's nothing left to do here except stop.
    totals = crawl_companies_and_calculate_distances(
      crawl_run, companies_to_crawl, search_lat, search_lng, radius_miles, options
    )
    return if totals.nil?

    # -------------------------------------------------------------------------
    # STEP 6: Check alert rules
    # -------------------------------------------------------------------------
    broadcast_log(crawl_run, :info, "system", "Checking alert rules...")

    # `AlertCheckerJob.perform_later(...)` ENQUEUES another background job
    # (see app/jobs/alert_checker_job.rb) to run, using `perform_later`
    # rather than `perform_now` means this CrawlJob doesn't wait around for
    # alert-checking to finish; it just schedules it and moves on
    # immediately to the steps below.
    AlertCheckerJob.perform_later(crawl_run_id: crawl_run.id)

    # STEP 7: Purge old history, see purge_old_crawl_history below.
    purge_old_crawl_history(crawl_run)

    # -------------------------------------------------------------------------
    # STEP 8: Mark complete
    # -------------------------------------------------------------------------
    # `crawl_run.complete!` flips the record's status to done, presumably
    # recording a completion timestamp too.
    crawl_run.complete!

    broadcast_status(
      crawl_run,
      "Crawl complete, #{totals[:facilities]} facilities, #{totals[:units]} matching units found"
    )

    # Broadcast a "done" event so the dashboard can refresh the results table
    broadcast_finished(crawl_run)

  rescue ActiveRecord::RecordNotFound => e
    # The crawl_run record was deleted before the job ran, nothing to do
    #
    # This `rescue` (and the one below) is attached directly to the
    # `def perform ... end` method body, Ruby allows a method definition
    # to have its own implicit begin/rescue without a separate `begin`
    # keyword, catching errors raised ANYWHERE in the method above.
    # ActiveRecord::RecordNotFound here specifically means the very first
    # `CrawlRun.find(crawl_run_id)` call at the top of this method failed
    # , since crawl_run was never successfully assigned, there's nothing
    # meaningful this rescue block can update; it just logs and stops.
    Rails.logger.error("[CrawlJob] CrawlRun ##{crawl_run_id} not found: #{e.message}")

  rescue => e
    # Something went very wrong at the top level, mark the crawl as failed
    #
    # Catch-all for any other unexpected error anywhere in `perform` (or
    # anything it calls) that wasn't already handled by a more specific
    # rescue (like the per-company rescues inside crawl_one_company below,
    # which don't let errors escape this far).
    error_msg = "#{e.class}: #{e.message}"
    Rails.logger.error("[CrawlJob] Fatal error: #{error_msg}\n#{e.backtrace.join("\n")}")

    # `begin ... rescue ... end` NESTED inside this outer rescue, this
    # protects against the possibility that even TRYING to mark the crawl
    # as failed (which itself hits the database and the broadcast system)
    # could itself raise an error (e.g. if the database connection is the
    # thing that's broken). Without this inner begin/rescue, such a
    # secondary failure would replace/mask the original error.
    begin
      # `crawl_run&.fail!(error_msg)`, safe navigation (`&.`) matters here
      # because if the RecordNotFound case above didn't happen but some
      # OTHER early failure meant `crawl_run` was never assigned, this
      # avoids raising a NoMethodError on nil; it simply does nothing if
      # crawl_run is nil.
      crawl_run&.fail!(error_msg)
      # If any data was collected before the failure, set completed_at so
      # the dashboard can still show partial results.
      if crawl_run&.facility_ids&.any?
        crawl_run.update_column(:completed_at, Time.current)
      end
      broadcast_status(crawl_run, "Crawl failed: #{error_msg}")
    rescue => inner_e
      Rails.logger.error("[CrawlJob] Could not even mark crawl as failed: #{inner_e.message}")
    end
    # `end` closes this inner `begin/rescue` block.

    raise  # Re-raise so ActiveJob knows the job failed (for retry logic)
    # A bare `raise` with no argument, inside a `rescue` block, re-raises
    # the SAME exception (`e`) that was just caught, this lets ActiveJob's
    # own error handling (specifically the `retry_on StandardError`
    # configured near the top of this class) see that the job failed and
    # potentially retry it, rather than silently swallowing the error here.
  end
  # `end` closes the `def perform` method definition, everything below is
  # the private, single-purpose methods `perform` delegates each STEP to.

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  # -------------------------------------------------------------------------
  # STEP 1 (extracted): Geocode the search city to lat/lng
  # -------------------------------------------------------------------------
  # "Geocoding" means converting a human-readable place (like "Gilbert,
  # Arizona") into precise latitude/longitude map coordinates.
  #
  # Returns a two-element Array `[search_lat, search_lng]` on success. On
  # failure (no geocoding matches at all), marks `crawl_run` failed and
  # broadcasts the error itself, then returns `nil`, `perform` above
  # checks for that `nil` and stops immediately, since nothing downstream
  # can proceed without coordinates.
  def geocode_search_location(crawl_run)
    search_city = crawl_run.search_city

    # `broadcast_log(crawl_run, :info, "system", "...")` sends one line to
    # the dashboard's live log feed (see the private method further down).
    # `:info` and `"system"` are, respectively, a log severity level symbol
    # and a label identifying this line isn't tied to any one company.
    broadcast_log(crawl_run, :info, "system", "Looking up coordinates for '#{search_city}'...")

    # `Geocoder.search(...)` calls the `geocoder` gem (a third-party
    # library) to look up real-world coordinates for the given place name,
    # returning an array of possible matches (often just one, but a place
    # name could be ambiguous).
    geocode_results = Geocoder.search(search_city)

    # `.empty?`, no matches came back at all, meaning geocoding failed
    # entirely for this input.
    if geocode_results.empty?
      # Geocoding failed, can't do anything without coordinates
      error_msg = "Could not find coordinates for '#{search_city}'. " \
                  "Try entering a full city name (e.g. 'Gilbert, Arizona') or a ZIP code."
      # `crawl_run.fail!(error_msg)` marks the crawl run as failed in the
      # database, recording the reason.
      crawl_run.fail!(error_msg)
      broadcast_status(crawl_run, error_msg)
      # Nothing more can be done without coordinates, signal failure to
      # the caller (`perform`), which stops here.
      return nil
    end
    # `end` closes the `if geocode_results.empty?` block above.

    # `.first` takes the top/best geocoding match from the results array.
    result = geocode_results.first
    # `.latitude`/`.longitude` are methods the geocoder gem adds to each
    # result object, giving the coordinate pair for that match.
    search_lat = result.latitude
    search_lng = result.longitude

    # Save the resolved coordinates back to the crawl run record
    #
    # `.update!(...)` saves these two columns on the crawl_run database
    # row. The `!` means it will raise an error if validation fails,
    # instead of silently returning false, appropriate here since a
    # failed save would be a real, unexpected problem worth surfacing.
    crawl_run.update!(search_lat: search_lat, search_lng: search_lng)

    broadcast_log(
      crawl_run, :info, "system",
      # `.round(4)` rounds each coordinate to 4 decimal places (about 11
      # meters of precision) purely for a cleaner, shorter log message.
      "Geocoded '#{search_city}' → #{search_lat.round(4)}, #{search_lng.round(4)}"
    )

    [ search_lat, search_lng ]
  end
  # `end` closes the `def geocode_search_location` method definition.

  # -------------------------------------------------------------------------
  # STEP 2 (extracted): Determine which companies to crawl
  # -------------------------------------------------------------------------
  # Returns the Array of company names to crawl this run, and (as a side
  # effect) saves that list onto `crawl_run` and logs it, this never fails
  # in a way that should stop the crawl, so unlike geocode_search_location
  # above it has no `nil`-means-failure return case.
  def resolve_companies_to_crawl(crawl_run, options)
    # `if ... else ... end` used here as an EXPRESSION whose result is
    # directly assigned to companies_to_crawl, in Ruby, `if/else` blocks
    # evaluate to the value of whichever branch actually ran, so this is
    # equivalent to (but more readable than) assigning inside each branch
    # separately.
    companies_to_crawl = if options[:companies].present?
      # User selected specific companies
      #
      # `options[:companies]` reads the `:companies` key out of the
      # `options` Hash passed into `perform`, if the user picked specific
      # companies via a form, this list comes through the job's arguments.
      options[:companies]
    else
      # Default: crawl all registered companies
      #
      # `CompanyRegistry.all_company_names` (see
      # app/services/company_registry.rb) returns every registered
      # company's display name.
      CompanyRegistry.all_company_names
    end
    # `end` closes the `if options[:companies].present? ... else ... end`
    # expression above.

    # Update the crawl run with the company list
    crawl_run.update!(companies_included: companies_to_crawl)

    broadcast_log(
      crawl_run, :info, "system",
      "Will crawl #{companies_to_crawl.length} companies: #{companies_to_crawl.join(", ")}"
    )

    companies_to_crawl
  end
  # `end` closes the `def resolve_companies_to_crawl` method definition.

  # -------------------------------------------------------------------------
  # STEP 3 (part 1, extracted): Locate the Playwright CLI executable
  # -------------------------------------------------------------------------
  # Find the playwright CLI, try npm global install location, then PATH.
  # Each shell-out is wrapped in the `timeout` coreutil so a stalled `npx`
  # (e.g. blocked on a registry fetch) can't hang the job before the
  # per-company/per-crawl deadlines below even start counting.
  #
  # Returns the executable path String on success, or `nil` on failure,
  # in which case (like geocode_search_location above) `crawl_run` has
  # already been marked failed and the error already broadcast, so the
  # caller just needs to stop.
  def find_playwright_executable(crawl_run)
    # Backticks run a shell command and capture its printed output as a
    # Ruby String (same technique used in recon_service.rb). `timeout 10
    # which playwright` looks for a globally-installed `playwright`
    # executable on the system PATH, capped at 10 seconds so a broken shell
    # environment can't hang this line forever. `2>/dev/null` discards
    # error output. `.strip` trims whitespace/newlines from the result.
    playwright_path = `timeout 10 which playwright 2>/dev/null`.strip

    # `.blank?`, Rails helper for nil-or-empty. If the plain `which`
    # lookup found nothing, fall back to trying `npx playwright` (npm's
    # tool for running a locally-installed package's CLI without a global
    # install).
    if playwright_path.blank?
      # `timeout 15 npx playwright --version 2>/dev/null && echo "npx
      # playwright"`, runs `npx playwright --version` (capped at 15
      # seconds); the shell `&&` means the following `echo` only runs if
      # the version check SUCCEEDED (exit code 0), so the echoed line only
      # appears on success. `.lines` splits the captured multi-line output
      # into an array of individual line strings; `.last` takes the final
      # line (which would be "npx playwright" if the whole command chain
      # succeeded, or some other line, like a version number, if `&&`
      # short-circuited due to the version check itself printing something
      # before failing, if it didn't). `&.strip` (safe navigation) trims
      # whitespace, guarding against `.last` being nil if there was no
      # output at all.
      playwright_path = `timeout 15 npx playwright --version 2>/dev/null && echo "npx playwright"`.lines.last&.strip
    end
    # `end` closes the `if playwright_path.blank?` block above.

    if playwright_path.blank?
      # Both lookup attempts failed, there's no way to launch a browser,
      # so fail the whole crawl with an actionable error message.
      error_msg = "Playwright CLI not found. Install it with: npm install -g playwright && playwright install chromium"
      crawl_run.fail!(error_msg)
      broadcast_status(crawl_run, error_msg)
      return nil
    end
    # `end` closes this second `if playwright_path.blank?` block.

    playwright_path
  end
  # `end` closes the `def find_playwright_executable` method definition.

  # -------------------------------------------------------------------------
  # STEPS 3-5 (extracted): Launch the browser, run every company's parser,
  # then calculate distances once they're all done
  # -------------------------------------------------------------------------
  # Returns `{ facilities: N, units: N }` totals across every company that
  # actually completed, or `nil` if the Playwright CLI couldn't be found at
  # all (see find_playwright_executable above), `perform` checks for that
  # `nil` and stops.
  def crawl_companies_and_calculate_distances(crawl_run, companies_to_crawl, search_lat, search_lng, radius_miles, options)
    broadcast_log(crawl_run, :info, "system", "Launching browser...")

    # `Setting.get("crawl_headless", default: "true") != false`, reads a
    # configurable app setting, and compares it to the literal value
    # `false`. Since Setting.get likely returns a STRING like "true" or
    # "false" (or possibly an actual boolean depending on how Setting
    # works), this comparison is really just checking "is the setting not
    # literally the false object", in practice this evaluates to `true`
    # for basically any string value including "false" the string (since a
    # non-empty string is never == the boolean false), so effectively
    # `headless` ends up true unless Setting.get somehow returns a real
    # `false` object. Flagged separately as worth double-checking, kept
    # exactly as-is here since fixing it is a behavior change, not a
    # comment/refactor cleanup, and outside this method-split's scope.
    headless = Setting.get("crawl_headless", default: "true") != false
    # `.to_i` converts the setting's value into an Integer, how many
    # companies to crawl in parallel via separate threads.
    max_parallel = Setting.get("crawl_parallel_companies", default: 2).to_i

    playwright_path = find_playwright_executable(crawl_run)
    return nil if playwright_path.nil?

    # These totals accumulate as run_company_thread_pool below crawls each
    # company, using a Hash (rather than two separate local variables)
    # means it can be passed BY REFERENCE into that method and mutated
    # there, then read back here once every company is done.
    totals = { facilities: 0, units: 0 }

    # `Playwright.create(...) do |playwright| ... end` starts the
    # Playwright driver process (using the executable path found above)
    # and yields a `playwright` control object usable inside the block.
    # Playwright automatically tears down the driver process once this
    # block finishes (successfully or via an error), similar to how Ruby
    # file handles are auto-closed by `File.open(...) do |f| ... end`.
    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      # `.chromium.launch(...)` starts an actual Chromium browser process.
      # Wrapped in a timeout so a broken launch can't hang forever.
      browser = Timeout.timeout(60) do
        playwright.chromium.launch(
          headless: headless,
          args: [
            "--no-sandbox",                    # Required in some Linux environments
            "--disable-setuid-sandbox",
            "--disable-dev-shm-usage",         # Prevents crashes on low-memory machines
            "--disable-gpu",                   # Not needed for headless, saves resources
            "--window-size=1280,800"           # Set a reasonable viewport
          ]
        )
        # `args:` is an Array of Chromium command-line flags, each string
        # is one flag, with an inline comment explaining why it's needed.
      end

      broadcast_log(crawl_run, :info, "system", "Browser launched successfully")

      # STEP 4: Run every company's parser via a thread pool, see
      # run_company_thread_pool below. Mutates `totals` in place as each
      # company finishes.
      run_company_thread_pool(
        crawl_run, companies_to_crawl, browser, search_lat, search_lng, radius_miles, options, max_parallel, totals
      )

      # -----------------------------------------------------------------------
      # STEP 5: Calculate distances
      # -----------------------------------------------------------------------
      broadcast_log(crawl_run, :info, "system", "Calculating distances from search origin...")

      # `Facility.calculate_distances_from(...)` is presumably a class
      # method on the Facility model that computes and saves the
      # straight-line (or driving) distance from each saved facility to
      # the search origin coordinates, now that all companies have
      # finished (or been skipped/timed out).
      Facility.calculate_distances_from(search_lat, search_lng)

      broadcast_log(crawl_run, :info, "system", "Distance calculation complete")

      # Close the browser now that we're done crawling
      #
      # Explicitly shuts down the shared Chromium browser process, done
      # here (rather than relying only on Playwright.create's automatic
      # cleanup) so the browser is closed as soon as crawling work is
      # truly finished, before this method returns.
      browser.close
    end # Playwright.create block ends here, browser is automatically closed
    # This trailing `end` closes the `Playwright.create(...) do
    # |playwright|` block that began above, every line of STEP 3 (browser
    # launch), STEP 4 (company crawling), and STEP 5 (distance calc)
    # happened inside this block, using the `playwright`/`browser` objects
    # it provided.

    totals
  end
  # `end` closes the `def crawl_companies_and_calculate_distances` method
  # definition.

  # -------------------------------------------------------------------------
  # STEP 4 (part 1, extracted): Thread-pool orchestration
  # -------------------------------------------------------------------------
  # We use a simple thread pool controlled by max_parallel.
  # On slow/old hardware, keep max_parallel at 1 or 2.
  #
  # This is the heart of the file's concurrency (multiple things happening
  # "at once") logic. It starts `max_parallel` worker threads, each of
  # which repeatedly claims and crawls one company at a time (via
  # crawl_one_company below) from a shared work queue until the queue is
  # empty or the crawl-wide deadline is hit, then waits for every thread to
  # finish (with a grace period, and a last-resort force-kill for any
  # thread that's still stuck afterward). Mutates `totals` (passed in from
  # crawl_companies_and_calculate_distances above) in place as each company
  # finishes, this method has no meaningful return value of its own.
  def run_company_thread_pool(crawl_run, companies_to_crawl, browser, search_lat, search_lng, radius_miles, options, max_parallel, totals)
    # `Mutex.new` creates a new lock object. See the big explanation at
    # the top of this file for what a Mutex does, in short, it ensures
    # that when multiple threads need to read-then-write the SAME shared
    # variable (like `totals` above, or the work queue built next), only
    # one thread does so at a time, preventing corrupted updates.
    mutex = Mutex.new                                       # Prevents race conditions when updating totals
    # `companies_to_crawl.dup` creates a SHALLOW COPY of the array,
    # important because this new array (`companies_queue`) is going to
    # be mutated (items removed from it one at a time as threads claim
    # work) while `companies_to_crawl` itself is left untouched (it's
    # still needed elsewhere, e.g. already saved to crawl_run earlier).
    companies_queue = companies_to_crawl.dup                # Work queue
    # `active_threads = []` will collect every Thread object created
    # below, so we can later wait for all of them and check if any are
    # still stuck running.
    active_threads = []

    # Absolute deadline for the whole crawl, computed once, before any
    # worker threads start, so every thread is racing against the same clock.
    #
    # `monotonic_now` is a private helper method defined near the bottom
    # of this file, it returns a steadily-increasing clock reading that
    # can't jump backward (unlike wall-clock time, which can be adjusted
    # by NTP synchronization), making it safe for measuring elapsed time.
    # Adding CRAWL_TIMEOUT_SECONDS gives an absolute point in time (in
    # this monotonic clock's units) after which the whole crawl should
    # stop picking up new work.
    crawl_deadline = monotonic_now + CRAWL_TIMEOUT_SECONDS

    # `max_parallel.times do ... end` runs the block exactly
    # `max_parallel` times in a row, this is how the "thread pool" size
    # is controlled: if max_parallel is 2, this loop runs twice, each
    # time starting one new worker thread, for 2 threads total working
    # through the same shared companies_queue.
    max_parallel.times do
      # `Thread.new do ... end` starts a brand-new thread. Code inside
      # this block runs concurrently with the main thread (the one
      # executing `perform` overall) and with any other worker threads
      # started by this same loop. Ruby continues on to the NEXT
      # iteration of `max_parallel.times` (starting the next thread)
      # immediately, without waiting for this thread's block to finish.
      thread = Thread.new do
        # `loop do ... end` is Ruby's infinite-loop construct, it keeps
        # running the block over and over until something inside it
        # calls `break` (or the thread is killed from outside). Each
        # pass through this loop, the thread tries to claim and process
        # ONE company from the shared queue.
        loop do
          # Stop picking up new companies once the overall crawl budget is spent.
          # Whatever's left in the queue is simply not crawled this run.
          #
          # Computes how much time is left before the whole-crawl
          # deadline, in seconds (could be negative if we're already
          # past it).
          remaining_total = crawl_deadline - monotonic_now
          if remaining_total <= 0
            # The crawl-wide time budget is used up, this thread logs a
            # warning (once, each time it discovers this) and stops
            # taking new work, leaving anything still in companies_queue
            # un-crawled.
            crawl_run.log_warning(
              "Overall crawl timeout (#{CRAWL_TIMEOUT_SECONDS}s) reached, " \
              "remaining companies were not crawled this run.",
              company: "system"
            )
            # `break` exits the `loop do ... end` entirely, this
            # thread's block then finishes, and the thread terminates.
            break
          end
          # `end` closes the `if remaining_total <= 0` block above.

          # Pull the next company from the queue (thread-safe via mutex)
          #
          # `mutex.synchronize do ... end`, because MULTIPLE threads run
          # this exact same loop body concurrently, and they're all
          # sharing the ONE `companies_queue` array, two threads could
          # otherwise both try to grab a company at the exact same
          # instant and corrupt the array, or both grab the SAME
          # company. Wrapping the shared-array access in
          # `mutex.synchronize` guarantees only one thread executes
          # `companies_queue.shift` at a time, every other thread
          # trying to enter a `synchronize` block on this same mutex
          # simply waits its turn.
          #
          # `.shift` removes and returns the FIRST element of the array
          # (mutating companies_queue in place), or returns nil if the
          # array is already empty. This is what makes companies_queue
          # work as a shared "work queue": every thread calls `.shift`
          # to atomically claim the next unclaimed company.
          company_name = mutex.synchronize { companies_queue.shift }
          # If shift returned nil, the queue is empty, no more work for
          # this thread to do, so it's done and exits its loop.
          break if company_name.nil?   # Queue is empty, this thread is done

          # Never let a single company run longer than COMPANY_TIMEOUT_SECONDS,
          # and never let it push past the overall crawl deadline either.
          #
          # `[ COMPANY_TIMEOUT_SECONDS, remaining_total ].min` takes the
          # SMALLER of the two values: the fixed per-company cap, or
          # whatever time is actually left in the whole-crawl budget,
          # whichever is more restrictive right now. `.clamp(1,
          # COMPANY_TIMEOUT_SECONDS)` then forces the result to be
          # between 1 second (minimum, so Timeout.timeout inside
          # crawl_one_company is never called with 0 or a negative
          # number, which would be invalid) and COMPANY_TIMEOUT_SECONDS
          # (maximum, redundant with the .min above but defensive).
          company_timeout = [ COMPANY_TIMEOUT_SECONDS, remaining_total ].min.clamp(1, COMPANY_TIMEOUT_SECONDS)

          # Crawl this one company, see crawl_one_company below. It
          # handles its OWN error cases internally (timeout, unknown
          # company, any other exception) and always returns a
          # `[facilities_count, units_count]` pair, `[0, 0]` if this
          # company failed for any reason, so there's no begin/rescue
          # needed here at all.
          facilities_found, units_found = crawl_one_company(
            crawl_run, company_name, browser, search_lat, search_lng, radius_miles, options, company_timeout
          )

          # Update totals (thread-safe)
          #
          # Using `mutex.synchronize do ... end` because `totals` is
          # shared across ALL worker threads, without the mutex, two
          # threads finishing at nearly the same moment could both read
          # the same starting value and one thread's update could get
          # silently overwritten/lost (the classic "race condition"
          # explained at the top of this file).
          mutex.synchronize do
            totals[:facilities] += facilities_found
            totals[:units]      += units_found
          end
          # `end` closes the `mutex.synchronize do` block above.
        end
        # `end` closes the `loop do` block, the infinite work-claiming
        # loop for this one worker thread. Once this is reached (via a
        # `break` above), the thread's block is finished and the thread
        # itself terminates.
      end
      # `end` closes the `Thread.new do` block, everything above this
      # point (from `thread = Thread.new do`) is the CODE THE NEW THREAD
      # WILL RUN; this `end` is where that thread's job description
      # stops. The `thread` local variable now holds a reference to the
      # running (or already-finished, if it was extremely fast) thread
      # object.

      # Adds this newly-created thread to the tracking array, so it can
      # be waited on / checked later after the loop below finishes
      # starting all of them.
      active_threads << thread
    end
    # `end` closes the `max_parallel.times do` loop, by this point,
    # `max_parallel` worker threads have all been STARTED (though they
    # may still be running/mid-crawl at this exact moment in the code,
    # starting a thread doesn't wait for it).

    # Wait for all threads to finish, but only up to a short grace period past
    # the crawl deadline. Timeout.timeout inside crawl_one_company should make
    # every thread exit on its own near crawl_deadline, but if Playwright is
    # stuck in a native call that Ruby can't interrupt, this is the backstop
    # that guarantees the job itself doesn't hang forever.
    #
    # `join_deadline = crawl_deadline + 10` adds a 10-second grace period
    # onto the crawl-wide deadline, giving threads a little extra time to
    # notice the timeout and wrap up cleanly before this code gives up
    # waiting on them.
    join_deadline = crawl_deadline + 10
    # `active_threads.each { |t| t.join(...) }` waits for each tracked
    # thread to finish, ONE AT A TIME, in the order they appear in the
    # array. `t.join(timeout_seconds)` is Thread#join with an argument:
    # normally `.join` (no argument) waits forever until the thread
    # finishes; passing a number caps how long to wait, if the thread
    # is still running after that many seconds, `.join` just gives up
    # and returns (WITHOUT killing the thread), letting this line move
    # on to `.join` the next thread in the array.
    # `[ join_deadline - monotonic_now, 0 ].max` computes "how many
    # seconds until join_deadline, but never less than 0", `.max` picks
    # the larger of the two values in the array, so once join_deadline
    # has already passed, every subsequent `.join` call here effectively
    # gets 0 seconds (meaning: check once and return immediately rather
    # than waiting further), instead of accidentally passing a NEGATIVE
    # number to `.join` (which Thread#join doesn't accept meaningfully).
    active_threads.each { |t| t.join([ join_deadline - monotonic_now, 0 ].max) }

    # `.select(&:alive?)` filters active_threads down to only the ones
    # STILL RUNNING after the joins above gave up waiting, `&:alive?`
    # is Ruby shorthand for `{ |t| t.alive? }` (turning the symbol
    # `:alive?` into a block that calls that method on each element).
    # `Thread#alive?` returns true if the thread hasn't finished yet.
    active_threads.select(&:alive?).each do |t|
      # Any thread reaching this point is one where Timeout.timeout
      # (inside crawl_one_company, running in that thread) apparently
      # failed to interrupt whatever native/blocking call it was stuck
      # in, and even the grace-period join above timed out waiting for
      # it. This is the last-resort backstop mentioned in the comment
      # above.
      crawl_run.log_warning(
        "A worker thread did not stop after the crawl timeout and was force-killed.",
        company: "system"
      )
      # `t.kill` forcibly terminates the thread from OUTSIDE it, unlike
      # Timeout.timeout (which relies on the target code cooperating at
      # certain interruption points), `.kill` is a blunter, more
      # forceful stop that doesn't require the thread's code to
      # cooperate, but can leave things in a partially-finished state
      # (e.g. a browser page left half-open) since it doesn't run any
      # cleanup code in that thread.
      t.kill
    end
    # `end` closes the `active_threads.select(&:alive?).each do |t|` loop.
  end
  # `end` closes the `def run_company_thread_pool` method definition.

  # -------------------------------------------------------------------------
  # STEP 4 (part 2, extracted): Crawl a single company
  # -------------------------------------------------------------------------
  # Builds this company's parser, runs it under a timeout, and updates the
  # crawl_run's per-company counters/log. ANY failure for this ONE company
  # (a crash, a timeout, an unrecognized company name) is caught here and
  # turned into a `[0, 0]` result instead of raising, so one bad company
  # can never take down the whole thread pool. Always returns a
  # `[facilities_count, units_count]` pair (both `0` on any failure).
  def crawl_one_company(crawl_run, company_name, browser, search_lat, search_lng, radius_miles, options, company_timeout)
    broadcast_log(
      crawl_run, :info, company_name,
      "Starting crawl for #{company_name}..."
    )

    # Build the parser for this company
    #
    # `CompanyRegistry.build_parser(...)` (see
    # app/services/company_registry.rb) looks up and instantiates
    # the right parser class for this company name, passing it
    # the shared browser object (note: the SAME browser instance
    # is shared across all worker threads, each parser presumably
    # opens its OWN page/tab within that one browser) plus the
    # crawl_run record and any user-supplied options.
    parser = CompanyRegistry.build_parser(
      company_name,
      crawl_run: crawl_run,
      browser:   browser,
      options:   options
    )

    # Run the parser, returns { facilities: N, units: N }
    #
    # `Timeout.timeout(company_timeout, CompanyTimeoutError) do
    # ... end` runs the block (the actual parser.run call) but
    # forcibly interrupts it if it hasn't finished within
    # `company_timeout` seconds. Passing `CompanyTimeoutError` as
    # the second argument tells Ruby to raise THAT specific
    # exception class (instead of Timeout's generic
    # Timeout::Error) when the timeout fires, which is what lets
    # the `rescue CompanyTimeoutError` clause below catch it
    # specifically. Under the hood, Timeout.timeout runs the
    # block, but also starts a background watcher that will
    # interrupt the block's thread if time runs out, this is a
    # best-effort mechanism: purely native/C-level code that
    # Ruby can't interrupt (mentioned again in run_company_thread_pool's
    # force-kill fallback) can still block past this timeout.
    result = Timeout.timeout(company_timeout, CompanyTimeoutError) do
      # `parser.run(...)` is the actual work: visits the
      # company's website, extracts facility/unit data, and
      # saves it, then returns a Hash like `{ facilities: 5,
      # units: 40 }` summarizing what it found.
      parser.run(
        search_lat:   search_lat,
        search_lng:   search_lng,
        radius_miles: radius_miles
      )
    end
    # `end` closes the `Timeout.timeout(...) do` block above.

    # Update crawl run counters (uses SQL increment, thread-safe)
    #
    # These three lines update the database directly rather than
    # updating plain Ruby variables, the comment notes these
    # particular model methods use a SQL-level increment (like
    # `UPDATE crawl_runs SET facilities_found =
    # facilities_found + 5`), which the database itself performs
    # atomically, so these calls are already safe to make from
    # multiple threads WITHOUT needing a mutex (unlike the totals
    # Hash accumulated back in run_company_thread_pool).
    crawl_run.increment_companies_crawled!
    crawl_run.increment_facilities!(result[:facilities].to_i)
    crawl_run.increment_units!(result[:units].to_i)

    broadcast_log(
      crawl_run, :info, company_name,
      "✓ #{company_name} complete: #{result[:facilities]} facilities, #{result[:units]} units"
    )

    # `.to_i` defensively converts whatever came back (in case it's nil or
    # already a different numeric type) to a plain Integer before handing
    # it back to run_company_thread_pool, which adds it into the shared
    # totals under its own mutex.
    [ result[:facilities].to_i, result[:units].to_i ]

  rescue CompanyTimeoutError
    # This company took longer than its time budget, whatever it had
    # saved so far stays saved, we just stop waiting on it and move on.
    #
    # This specifically catches the exception raised by
    # `Timeout.timeout` above when `company_timeout` seconds
    # elapsed without the block finishing.
    crawl_run.log_error(
      "#{company_name} timed out after #{company_timeout.round}s and was skipped so the " \
      "crawl could keep moving. This can happen on sites with many locations or slow pages, " \
      "consider excluding this company or lowering crawl_delay_between_requests_ms in Settings.",
      company: company_name
    )
    crawl_run.increment_companies_failed!

    broadcast_log(
      crawl_run, :error, company_name,
      "✗ #{company_name} timed out, skipped"
    )

    [ 0, 0 ]

  rescue ArgumentError => e
    # CompanyRegistry couldn't find a parser, log and skip
    #
    # `CompanyRegistry.build_parser` (called above) raises
    # ArgumentError if `company_name` isn't a registered company
    # , this branch catches that specific case.
    crawl_run.log_error(
      "No parser found for '#{company_name}': #{e.message}",
      company: company_name
    )
    crawl_run.increment_companies_failed!

    [ 0, 0 ]

  rescue => e
    # Unexpected error, log it but keep going with other companies
    #
    # A catch-all for anything else that could go wrong while
    # crawling this one company (a bug in the parser, a network
    # error that isn't a timeout, etc.), logs it with as much
    # detail as reasonably fits, then returns `[0, 0]` so the
    # caller's loop continues to the next company rather than
    # crashing this whole worker thread.
    crawl_run.log_error(
      "Unexpected error crawling #{company_name}: #{e.class}: #{e.message}. " \
      "This company will be skipped. Backtrace: #{e.backtrace.first(3).join(" | ")}",
      company: company_name
    )
    crawl_run.increment_companies_failed!

    broadcast_log(
      crawl_run, :error, company_name,
      "✗ #{company_name} failed, see logs for details"
    )

    [ 0, 0 ]
  end
  # `end` closes the `def crawl_one_company` method definition (including
  # its attached `rescue` clauses).

  # -------------------------------------------------------------------------
  # STEP 7 (extracted): Purge old history
  # -------------------------------------------------------------------------
  # Delete crawl data older than the configured retention period.
  def purge_old_crawl_history(crawl_run)
    months_to_keep = Setting.get("history_keep_months", default: 6).to_i
    # `months_to_keep.months.ago`, `.months` is an ActiveSupport
    # (Rails-added) method on Integer that turns "6" into a Duration
    # representing "6 months," and `.ago` computes the Time that many
    # months before right now, so cutoff_date ends up being, e.g., "6
    # months ago from today."
    cutoff_date = months_to_keep.months.ago

    # `.where("created_at < ?", cutoff_date)` filters to crawl runs created
    # before that cutoff. `.completed` further narrows to only ones that
    # actually finished successfully (presumably we don't want to purge
    # in-progress or failed runs the same way).
    old_runs = CrawlRun.where("created_at < ?", cutoff_date).completed
    # `.count` runs a SQL COUNT query to see how many rows matched, without
    # loading the actual records into memory yet.
    old_count = old_runs.count

    if old_count > 0
      # `.destroy_all` loads and deletes every matching record one at a
      # time (running any model callbacks, unlike the faster but
      # callback-skipping `.delete_all`). This also destroys associated
      # units via dependent: :destroy
      old_runs.destroy_all  # This also destroys associated units via dependent: :destroy
      broadcast_log(
        crawl_run, :info, "system",
        "Purged #{old_count} old crawl run(s) older than #{months_to_keep} months"
      )
    end
    # `end` closes the `if old_count > 0` block above.
  end
  # `end` closes the `def purge_old_crawl_history` method definition.

  # Monotonic clock for measuring elapsed/remaining time. Unlike Time.current,
  # this can't jump backwards or forwards (NTP adjustments, etc.), so it's safe
  # to use for deadline math.
  def monotonic_now
    # `Process.clock_gettime(Process::CLOCK_MONOTONIC)` is Ruby's
    # standard-library way to read a "monotonic clock", a clock that only
    # ever moves FORWARD at a steady rate, unaffected by the system's
    # wall-clock time being adjusted (e.g. by automatic time
    # synchronization, daylight saving changes, or someone manually
    # changing the system clock). It returns a Float number of seconds
    # since some arbitrary starting point (not tied to any real calendar
    # date), only useful for measuring DIFFERENCES between two readings
    # of it, which is exactly how it's used throughout this file (e.g.
    # `crawl_deadline = monotonic_now + CRAWL_TIMEOUT_SECONDS`, then later
    # compared against a fresh `monotonic_now` call to see how much time
    # has elapsed).
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
  # `end` closes the `def monotonic_now` method definition above.

  # Broadcast the overall crawl status to the dashboard
  # This updates the status banner at the top of the page
  def broadcast_status(crawl_run, message)
    # `ActionCable.server.broadcast(channel_name, data)` sends a real-time
    # message to any connected browser tabs currently subscribed to the
    # given channel, ActionCable is Rails' built-in WebSocket framework,
    # used here to push live updates to the dashboard page WITHOUT the
    # browser needing to repeatedly poll/refresh. `"crawl_progress_#{crawl_run.id}"`
    # builds a channel name unique to this specific crawl run, so only
    # browser tabs watching THIS crawl's dashboard page receive these
    # particular updates.
    ActionCable.server.broadcast(
      "crawl_progress_#{crawl_run.id}",
      {
        type:       "status",
        message:    message,
        status:     crawl_run.status,
        facilities: crawl_run.facilities_found,
        units:      crawl_run.units_found
      }
      # This Hash is the actual payload sent to subscribed browsers,
      # ActionCable serializes it (turns it into JSON) automatically for
      # transmission over the WebSocket connection. `type: "status"`
      # tells the browser-side JavaScript which kind of update this is,
      # so it can update the right part of the page.
    )
  rescue => e
    # Don't let broadcast failures crash the crawl
    #
    # If ActionCable itself has a problem (e.g. Redis, which ActionCable
    # commonly relies on, is unavailable), that shouldn't be allowed to
    # crash the actual crawl, broadcasting live progress is a "nice to
    # have," not essential to the crawl succeeding, so failures here are
    # just logged and swallowed.
    Rails.logger.warn("[CrawlJob] Could not broadcast status: #{e.message}")
  end
  # `end` closes the `def broadcast_status` method definition above.

  # Broadcast a single log line to the dashboard's live log feed
  def broadcast_log(crawl_run, level, company, message)
    ActionCable.server.broadcast(
      "crawl_progress_#{crawl_run.id}",
      {
        type:      "log",
        # `level.to_s` converts the `level` argument (passed as a symbol
        # like `:info` or `:error` throughout this file) into a plain
        # String, since the receiving JavaScript on the dashboard likely
        # expects a string value rather than needing to understand Ruby
        # symbols (which don't exist as a concept in JSON/JavaScript).
        level:     level.to_s,
        company:   company,
        message:   message,
        # `Time.current.strftime("%H:%M:%S")` formats the current time as
        # just hours:minutes:seconds (24-hour), for a compact timestamp
        # next to each log line in the dashboard's live feed.
        timestamp: Time.current.strftime("%H:%M:%S")
      }
    )
  rescue => e
    Rails.logger.warn("[CrawlJob] Could not broadcast log: #{e.message}")
  end
  # `end` closes the `def broadcast_log` method definition above.

  # Broadcast a "finished" event so the dashboard knows to reload the results table
  def broadcast_finished(crawl_run)
    ActionCable.server.broadcast(
      "crawl_progress_#{crawl_run.id}",
      {
        type:       "finished",
        crawl_run_id: crawl_run.id,
        facilities: crawl_run.facilities_found,
        units:      crawl_run.units_found,
        # `crawl_run.duration_label` is presumably a model method that
        # formats how long the crawl took into a human-readable string
        # (e.g. "4m 12s").
        duration:   crawl_run.duration_label
      }
    )
  rescue => e
    Rails.logger.warn("[CrawlJob] Could not broadcast finished event: #{e.message}")
  end
  # `end` closes the `def broadcast_finished` method definition above.
end
# `end` closes the `class CrawlJob` definition that started at the top of
# this file, this is the very last line of the file.
