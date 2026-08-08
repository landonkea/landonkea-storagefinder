# =============================================================================
# SCHEDULED CRAWL CHECK JOB
# =============================================================================
# This is the job that wires up the "scheduler" Setting rows (seeded in
# db/seeds.rb — schedule_enabled / schedule_cron / schedule_city /
# schedule_radius_miles) to actual behavior. Before this job existed, those
# four settings were rendered on the Settings page and saved to the
# database, but nothing ever read them back — a user could flip
# "Enable scheduled automatic crawls" on and it would silently do nothing.
#
# HOW IT RUNS: config/recurring.yml tells Solid Queue (see the `gem
# "solid_queue"` comment in the Gemfile) to enqueue this job once every
# minute, in production/staging only. Each time it runs, it checks whether
# THIS PARTICULAR MINUTE matches the configured cron schedule — if so, and
# scheduling is enabled, it kicks off a crawl exactly the same way a human
# clicking "Run Crawl" on the dashboard would (see CrawlsController#create,
# which this method's crawl-building logic mirrors).
#
# WHY A ONE-MINUTE POLLING JOB INSTEAD OF SCHEDULING CrawlJob DIRECTLY AT
# THE CONFIGURED TIME: schedule_cron is a Setting a user can change anytime
# from the Settings page. Solid Queue's own recurring-task schedule (in
# config/recurring.yml) is static YAML, read once at boot — it has no way to
# notice a database row changed. Polling once a minute and checking the
# CURRENT database value of schedule_cron against the current time is what
# lets the schedule stay editable at runtime without restarting the app.
#
# `require "fugit"` loads the cron-parsing library Solid Queue itself
# depends on (see Gemfile.lock) for its own recurring-task schedule
# strings — it's a real dependency already present via solid_queue, but
# Rails doesn't auto-require every transitive gem dependency, so it's
# required explicitly here before `Fugit` is used below.
require "fugit"

class ScheduledCrawlCheckJob < ApplicationJob
  queue_as :default

  def perform
    # If the user hasn't opted in, do nothing — matches db/seeds.rb's
    # schedule_enabled default of "false" (off until explicitly enabled).
    return unless Setting.enabled?("schedule_enabled")

    cron_expression = Setting.get("schedule_cron", default: "0 6 * * *")
    cron = Fugit.parse_cron(cron_expression)

    if cron.nil?
      # A user could save garbage into the schedule_cron text field (it's a
      # plain text input, not validated as cron syntax — see db/seeds.rb's
      # own note on this). Fail loudly to the log instead of raising and
      # spamming Solid Queue's failed-jobs table every single minute.
      Rails.logger.error("[ScheduledCrawlCheckJob] Invalid schedule_cron value: #{cron_expression.inspect} — skipping")
      return
    end

    # Fugit::Cron#match? checks whether the given time is EXACTLY a tick of
    # this cron schedule — which, for a 5-field expression like Solid
    # Queue's, means second == 0 of a matching minute. This job runs once a
    # minute (see config/recurring.yml) but not necessarily at :00 exactly
    # (Solid Queue's dispatcher has its own small polling jitter — see
    # config/queue.yml), so calling `cron.match?(Time.current)` directly
    # would almost always see a nonzero seconds value and (wrongly) never
    # match. `.beginning_of_minute` rounds down to :00 first, so this
    # checks "does the current MINUTE match the schedule," matching this
    # job's own once-a-minute polling granularity instead of requiring the
    # literal current second to be zero.
    return unless cron.match?(Time.current.beginning_of_minute)

    if CrawlRun.any_running?
      Rails.logger.info("[ScheduledCrawlCheckJob] Schedule matched, but a crawl is already running — skipping this run")
      return
    end

    city = Setting.get("schedule_city", default: "").presence || CrawlRun.recent.first&.search_city

    if city.blank?
      Rails.logger.warn("[ScheduledCrawlCheckJob] Schedule matched, but schedule_city is blank and no previous manual search exists to fall back on — skipping")
      return
    end

    radius = Setting.get("schedule_radius_miles", default: 100)

    # Same default filter shape CrawlsController#create builds when a human
    # submits the dashboard form with every checkbox left at its default —
    # all sizes, climate-controlled only, every registered company.
    options = {
      sizes:              Unit::DEFAULT_SIZES,
      climate_controlled: true,
      companies:          nil,
      exclude_types:      Unit::EXCLUDED_TYPES
    }

    crawl_run = CrawlRun.create!(
      search_city:         city,
      search_radius_miles: radius,
      status:              "pending",
      filter_options:      options,
      companies_included:  CompanyRegistry.all_company_names
    )

    Rails.logger.info("[ScheduledCrawlCheckJob] Scheduled crawl triggered: CrawlRun ##{crawl_run.id} for '#{city}' within #{radius} miles")

    CrawlJob.perform_later(crawl_run_id: crawl_run.id, options: options)
  end
end
