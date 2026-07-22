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
# =============================================================================

require "timeout"

class CrawlJob < ApplicationJob
  # Raised when a single company's crawl (or the crawl as a whole) blows past
  # its time budget. Caught internally — it never bubbles up to ActiveJob, so it
  # does not trigger the retry_on StandardError below.
  class CompanyTimeoutError < StandardError; end

  # Use the "crawl" queue — ActiveJob's async adapter will process jobs from this queue
  queue_as :crawl

  # Retry configuration:
  # If the job crashes unexpectedly (NOT a per-company error — those are caught internally),
  # retry up to 2 times with exponential backoff (5 min, 25 min)
  retry_on StandardError, attempts: 2, wait: :polynomially_longer

  # Don't retry Playwright installation errors — those need manual intervention
  discard_on Playwright::Error

  # Hard cap on how long a single company's parser.run can take. Sites vary a
  # lot in how many locations they have and how slow their pages load — this
  # exists so one bad/slow company can't sit there forever instead of moving
  # on to the next one.
  COMPANY_TIMEOUT_SECONDS = 120 # 2 minutes

  # Hard cap on the whole crawl (all companies combined). Once this elapses,
  # worker threads stop picking up new companies — whatever hasn't run yet is
  # skipped and logged rather than left to run indefinitely.
  CRAWL_TIMEOUT_SECONDS = 300 # 5 minutes

  # ---------------------------------------------------------------------------
  # PERFORM
  # ---------------------------------------------------------------------------
  # This is the method ActiveJob calls to run the job.
  # Arguments come from CrawlJob.perform_later(crawl_run_id: ..., options: ...)
  # ---------------------------------------------------------------------------
  def perform(crawl_run_id:, options: {})
    # Fetch the CrawlRun record from the database
    # Use find! so we get a clear error if the ID doesn't exist
    crawl_run = CrawlRun.find(crawl_run_id)

    # Double-check it's not already running (in case of race condition)
    if crawl_run.running?
      Rails.logger.warn("[CrawlJob] CrawlRun ##{crawl_run_id} is already running — aborting duplicate job")
      return
    end

    # Mark the crawl as started
    crawl_run.start!
    broadcast_status(crawl_run, "Crawl started — geocoding search location...")

    # -------------------------------------------------------------------------
    # STEP 1: Geocode the search city to lat/lng
    # -------------------------------------------------------------------------
    search_city   = crawl_run.search_city
    radius_miles  = crawl_run.search_radius_miles || 100

    broadcast_log(crawl_run, :info, "system", "Looking up coordinates for '#{search_city}'...")

    geocode_results = Geocoder.search(search_city)

    if geocode_results.empty?
      # Geocoding failed — can't do anything without coordinates
      error_msg = "Could not find coordinates for '#{search_city}'. " \
                  "Try entering a full city name (e.g. 'Gilbert, Arizona') or a ZIP code."
      crawl_run.fail!(error_msg)
      broadcast_status(crawl_run, error_msg)
      return
    end

    result     = geocode_results.first
    search_lat = result.latitude
    search_lng = result.longitude

    # Save the resolved coordinates back to the crawl run record
    crawl_run.update!(search_lat: search_lat, search_lng: search_lng)

    broadcast_log(
      crawl_run, :info, "system",
      "Geocoded '#{search_city}' → #{search_lat.round(4)}, #{search_lng.round(4)}"
    )

    # -------------------------------------------------------------------------
    # STEP 2: Determine which companies to crawl
    # -------------------------------------------------------------------------
    companies_to_crawl = if options[:companies].present?
      # User selected specific companies
      options[:companies]
    else
      # Default: crawl all registered companies
      CompanyRegistry.all_company_names
    end

    # Update the crawl run with the company list
    crawl_run.update!(companies_included: companies_to_crawl)

    broadcast_log(
      crawl_run, :info, "system",
      "Will crawl #{companies_to_crawl.length} companies: #{companies_to_crawl.join(", ")}"
    )

    # -------------------------------------------------------------------------
    # STEP 3: Launch Playwright browser
    # -------------------------------------------------------------------------
    broadcast_log(crawl_run, :info, "system", "Launching browser...")

    headless     = Setting.get("crawl_headless", default: "true") != false
    max_parallel = Setting.get("crawl_parallel_companies", default: 2).to_i

    # We'll collect totals as we go
    total_facilities = 0
    total_units      = 0

    # Find the playwright CLI — try npm global install location, then PATH.
    # Each shells out is wrapped in the `timeout` coreutil so a stalled `npx`
    # (e.g. blocked on a registry fetch) can't hang the job before the
    # per-company/per-crawl deadlines below even start counting.
    playwright_path = `timeout 10 which playwright 2>/dev/null`.strip
    if playwright_path.blank?
      playwright_path = `timeout 15 npx playwright --version 2>/dev/null && echo "npx playwright"`.lines.last&.strip
    end
    if playwright_path.blank?
      error_msg = "Playwright CLI not found. Install it with: npm install -g playwright && playwright install chromium"
      crawl_run.fail!(error_msg)
      broadcast_status(crawl_run, error_msg)
      return
    end

    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      browser = playwright.chromium.launch(
        headless: headless,
        args: [
          "--no-sandbox",                    # Required in some Linux environments
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",         # Prevents crashes on low-memory machines
          "--disable-gpu",                   # Not needed for headless, saves resources
          "--window-size=1280,800"           # Set a reasonable viewport
        ]
      )

      broadcast_log(crawl_run, :info, "system", "Browser launched successfully")

      # -----------------------------------------------------------------------
      # STEP 4: Run company parsers
      # -----------------------------------------------------------------------
      # We use a simple thread pool controlled by max_parallel.
      # On slow/old hardware, keep max_parallel at 1 or 2.
      # -----------------------------------------------------------------------
      mutex            = Mutex.new                            # Prevents race conditions when updating totals
      companies_queue  = companies_to_crawl.dup              # Work queue
      active_threads   = []

      # Absolute deadline for the whole crawl — computed once, before any
      # worker threads start, so every thread is racing against the same clock.
      crawl_deadline = monotonic_now + CRAWL_TIMEOUT_SECONDS

      max_parallel.times do
        thread = Thread.new do
          loop do
            # Stop picking up new companies once the overall crawl budget is spent.
            # Whatever's left in the queue is simply not crawled this run.
            remaining_total = crawl_deadline - monotonic_now
            if remaining_total <= 0
              crawl_run.log_warning(
                "Overall crawl timeout (#{CRAWL_TIMEOUT_SECONDS}s) reached — " \
                "remaining companies were not crawled this run.",
                company: "system"
              )
              break
            end

            # Pull the next company from the queue (thread-safe via mutex)
            company_name = mutex.synchronize { companies_queue.shift }
            break if company_name.nil?   # Queue is empty — this thread is done

            begin
              broadcast_log(
                crawl_run, :info, company_name,
                "Starting crawl for #{company_name}..."
              )

              # Build the parser for this company
              parser = CompanyRegistry.build_parser(
                company_name,
                crawl_run: crawl_run,
                browser:   browser,
                options:   options
              )

              # Never let a single company run longer than COMPANY_TIMEOUT_SECONDS,
              # and never let it push past the overall crawl deadline either.
              company_timeout = [ COMPANY_TIMEOUT_SECONDS, remaining_total ].min.clamp(1, COMPANY_TIMEOUT_SECONDS)

              # Run the parser — returns { facilities: N, units: N }
              result = Timeout.timeout(company_timeout, CompanyTimeoutError) do
                parser.run(
                  search_lat:   search_lat,
                  search_lng:   search_lng,
                  radius_miles: radius_miles
                )
              end

              # Update totals (thread-safe)
              mutex.synchronize do
                total_facilities += result[:facilities].to_i
                total_units      += result[:units].to_i
              end

              # Update crawl run counters (uses SQL increment — thread-safe)
              crawl_run.increment_companies_crawled!
              crawl_run.increment_facilities!(result[:facilities].to_i)
              crawl_run.increment_units!(result[:units].to_i)

              broadcast_log(
                crawl_run, :info, company_name,
                "✓ #{company_name} complete: #{result[:facilities]} facilities, #{result[:units]} units"
              )

            rescue CompanyTimeoutError
              # This company took longer than its time budget — whatever it had
              # saved so far stays saved, we just stop waiting on it and move on.
              crawl_run.log_error(
                "#{company_name} timed out after #{company_timeout.round}s and was skipped so the " \
                "crawl could keep moving. This can happen on sites with many locations or slow pages — " \
                "consider excluding this company or lowering crawl_delay_between_requests_ms in Settings.",
                company: company_name
              )
              crawl_run.increment_companies_failed!

              broadcast_log(
                crawl_run, :error, company_name,
                "✗ #{company_name} timed out — skipped"
              )

            rescue ArgumentError => e
              # CompanyRegistry couldn't find a parser — log and skip
              crawl_run.log_error(
                "No parser found for '#{company_name}': #{e.message}",
                company: company_name
              )
              crawl_run.increment_companies_failed!

            rescue => e
              # Unexpected error — log it but keep going with other companies
              crawl_run.log_error(
                "Unexpected error crawling #{company_name}: #{e.class}: #{e.message}. " \
                "This company will be skipped. Backtrace: #{e.backtrace.first(3).join(" | ")}",
                company: company_name
              )
              crawl_run.increment_companies_failed!

              broadcast_log(
                crawl_run, :error, company_name,
                "✗ #{company_name} failed — see logs for details"
              )
            end
          end
        end

        active_threads << thread
      end

      # Wait for all threads to finish, but only up to a short grace period past
      # the crawl deadline. Timeout.timeout above should make every thread exit
      # on its own near crawl_deadline, but if Playwright is stuck in a native
      # call that Ruby can't interrupt, this is the backstop that guarantees the
      # job itself doesn't hang forever.
      join_deadline = crawl_deadline + 10
      active_threads.each { |t| t.join([ join_deadline - monotonic_now, 0 ].max) }

      active_threads.select(&:alive?).each do |t|
        crawl_run.log_warning(
          "A worker thread did not stop after the crawl timeout and was force-killed.",
          company: "system"
        )
        t.kill
      end

      # -----------------------------------------------------------------------
      # STEP 5: Calculate distances
      # -----------------------------------------------------------------------
      broadcast_log(crawl_run, :info, "system", "Calculating distances from search origin...")

      Facility.calculate_distances_from(search_lat, search_lng)

      broadcast_log(crawl_run, :info, "system", "Distance calculation complete")

      # Close the browser now that we're done crawling
      browser.close
    end # Playwright.create block ends here — browser is automatically closed

    # -------------------------------------------------------------------------
    # STEP 6: Check alert rules
    # -------------------------------------------------------------------------
    broadcast_log(crawl_run, :info, "system", "Checking alert rules...")

    AlertCheckerJob.perform_later(crawl_run_id: crawl_run.id)

    # -------------------------------------------------------------------------
    # STEP 7: Purge old history
    # -------------------------------------------------------------------------
    # Delete crawl data older than the configured retention period
    months_to_keep = Setting.get("history_keep_months", default: 6).to_i
    cutoff_date    = months_to_keep.months.ago

    old_runs = CrawlRun.where("created_at < ?", cutoff_date).completed
    old_count = old_runs.count

    if old_count > 0
      old_runs.destroy_all  # This also destroys associated units via dependent: :destroy
      broadcast_log(
        crawl_run, :info, "system",
        "Purged #{old_count} old crawl run(s) older than #{months_to_keep} months"
      )
    end

    # -------------------------------------------------------------------------
    # STEP 8: Mark complete
    # -------------------------------------------------------------------------
    crawl_run.complete!

    broadcast_status(
      crawl_run,
      "Crawl complete — #{total_facilities} facilities, #{total_units} matching units found"
    )

    # Broadcast a "done" event so the dashboard can refresh the results table
    broadcast_finished(crawl_run)

  rescue ActiveRecord::RecordNotFound => e
    # The crawl_run record was deleted before the job ran — nothing to do
    Rails.logger.error("[CrawlJob] CrawlRun ##{crawl_run_id} not found: #{e.message}")

  rescue => e
    # Something went very wrong at the top level — mark the crawl as failed
    error_msg = "#{e.class}: #{e.message}"
    Rails.logger.error("[CrawlJob] Fatal error: #{error_msg}\n#{e.backtrace.join("\n")}")

    begin
      crawl_run&.fail!(error_msg)
      broadcast_status(crawl_run, "Crawl failed: #{error_msg}")
    rescue => inner_e
      Rails.logger.error("[CrawlJob] Could not even mark crawl as failed: #{inner_e.message}")
    end

    raise  # Re-raise so ActiveJob knows the job failed (for retry logic)
  end

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  # Monotonic clock for measuring elapsed/remaining time. Unlike Time.current,
  # this can't jump backwards or forwards (NTP adjustments, etc.), so it's safe
  # to use for deadline math.
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Broadcast the overall crawl status to the dashboard
  # This updates the status banner at the top of the page
  def broadcast_status(crawl_run, message)
    ActionCable.server.broadcast(
      "crawl_progress_#{crawl_run.id}",
      {
        type:       "status",
        message:    message,
        status:     crawl_run.status,
        facilities: crawl_run.facilities_found,
        units:      crawl_run.units_found
      }
    )
  rescue => e
    # Don't let broadcast failures crash the crawl
    Rails.logger.warn("[CrawlJob] Could not broadcast status: #{e.message}")
  end

  # Broadcast a single log line to the dashboard's live log feed
  def broadcast_log(crawl_run, level, company, message)
    ActionCable.server.broadcast(
      "crawl_progress_#{crawl_run.id}",
      {
        type:      "log",
        level:     level.to_s,
        company:   company,
        message:   message,
        timestamp: Time.current.strftime("%H:%M:%S")
      }
    )
  rescue => e
    Rails.logger.warn("[CrawlJob] Could not broadcast log: #{e.message}")
  end

  # Broadcast a "finished" event so the dashboard knows to reload the results table
  def broadcast_finished(crawl_run)
    ActionCable.server.broadcast(
      "crawl_progress_#{crawl_run.id}",
      {
        type:       "finished",
        crawl_run_id: crawl_run.id,
        facilities: crawl_run.facilities_found,
        units:      crawl_run.units_found,
        duration:   crawl_run.duration_label
      }
    )
  rescue => e
    Rails.logger.warn("[CrawlJob] Could not broadcast finished event: #{e.message}")
  end
end
