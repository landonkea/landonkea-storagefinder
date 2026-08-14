# Feature Ideas

Concrete additions for StorageFinder, grounded in what's actually in the
schema and codebase today (not generic "add notifications" filler). Each
one below notes what existing data or code it'd build on.

1. **Per-unit and per-facility price-history sparklines.** The dashboard
   already has `build_price_history` in `DashboardController`, but it's a
   market-wide weekly average across default sizes, not tied to any one
   unit or facility. Every `Unit` row already carries `collected_at` and
   `monthly_price` across crawls, enough to draw a small line chart next
   to a specific unit or facility showing its own price over time, not
   just the market's.

2. **Price-drop badge vs. first-seen price.** Same underlying data as
   above: compare a unit's current `monthly_price` against the earliest
   `monthly_price` recorded for a unit at that facility/size, and show
   "$40 below where this started" directly on the results table instead
   of making the user infer it from the history chart.

3. **More than one saved search running on its own schedule.** Right now
   `schedule_enabled`/`schedule_cron`/`schedule_city`/`schedule_radius_miles`
   are singleton `Setting` rows, one schedule for the whole app. Someone
   comparing a current-home storage unit against a future-move city can't
   track both on autopilot today. A `SavedSearch` model (city, radius,
   company filter, cron, its own alert rules) would let
   `ScheduledCrawlCheckJob` iterate several instead of reading one fixed
   set of Settings.

4. **All-in monthly cost column.** `monthly_price` and `admin_fee` are
   separate columns on `Unit`; nothing currently adds them together for
   comparison. A facility with a low sticker price and a $25 admin fee can
   easily lose to one with a higher price and no fee, sorting/filtering
   by `monthly_price` alone hides that.

5. **"What changed since last crawl" summary.** `crawl_log_entries`
   records per-company success/failure, but nothing surfaces, in plain
   language, "3 units disappeared from Public Storage on Main St, 2 new
   units appeared at CubeSmart" between two `CrawlRun`s. That's derivable
   by diffing `Unit` records grouped by `facility_id` + `size` across two
   `crawl_run_id`s, without needing new columns.

6. **Manual per-facility notes.** This is a single-user tool, there's no
   reason a facility can't carry a free-text note field ("called, gate
   code was broken," "no elevator to 2nd floor despite listing") the
   crawler will never learn on its own. A `notes` text column on
   `Facility` plus a small textarea on its detail view covers it.

7. **Side-by-side unit comparison.** The results table already supports
   sorting/filtering; adding checkboxes to select 2-4 units and a
   comparison view (size, price, admin fee, distance, climate-controlled,
   drive-up, indoor, all already columns on `Unit`) would help more than
   another sort option once someone's down to a short list.

8. **Shareable saved-search links on the public search page.**
   `PublicSearchController#index` already builds results from query
   params (city, radius, filters). Persisting one of those as a short,
   sharable slug (a `SharedSearch` model mapping a token to the param
   set) means a search can be texted to someone else without them typing
   an address in.

9. **A push-notification channel that doesn't need a paid account.**
   `AlertRule` already has `email_enabled`, `discord_enabled`, and
   `sms_enabled` (SMS is stubbed, `alert_delivery_service.rb` notes it
   needs paid Twilio). ntfy.sh or Pushover both work with a plain HTTP
   POST and no paid tier, a real alternative delivery channel that
   actually ships, versus SMS which currently can't.

10. **Driving-time distance as an alternative to straight-line miles.**
    `Facility#distance_miles` comes from the geocoder gem's straight-line
    calculation. Two facilities at the same straight-line distance can
    differ by 15 minutes of actual driving depending on what's between
    them, worth an opt-in routing-API lookup for the facilities someone's
    actually considering, not every result.

11. **Promo-text change detection, independent of price.** `Unit` has
    `web_special_note` as its own column, separate from
    `web_special_price`. A facility can swap "first month free" for
    "50% off first 3 months" without the listed price changing at all,
    currently invisible unless someone reads the raw text on every crawl.
    Diffing `web_special_note` between crawls the same way as unit
    appearance/disappearance (idea 5) would catch it.

12. **A digest email**, separate from per-rule alerts. `AlertRule`
    already fires on specific triggers; nothing currently sends "here's
    what this week's crawls found" as a standalone summary (new lowest
    price seen, biggest single-unit drop, facility count, crawl success
    rate). Useful even with zero alert rules configured.

13. **Scheduled, emailed exports.** `ExportsController#csv`/`#excel`
    already build a full export on demand from `build_csv`, but only
    when someone clicks the button. Wiring the same builder into a
    recurring Solid Queue task that emails the file (weekly, say) turns
    it into a standing record instead of something only pulled manually.

14. **A pinned watchlist.** Favoriting specific units or facilities so
    they stay visible at the top of the dashboard regardless of whatever
    filters are currently applied, useful once a search has narrowed down
    to a handful of real contenders and the rest of the noise stops
    mattering.

15. **Per-company scraper reliability score.** `crawl_log_entries` already
    tracks `success`/`level`/`retry_count` per company per crawl. Nothing
    currently rolls that up into "Extra Space has failed 8 of the last 10
    crawls" (which, per `BUILD_LOG.md`, is currently true, it's CAPTCHA-
    blocked). Surfacing that on the dashboard would tell the user which
    sources to actually trust versus which are silently returning stale
    data.

16. **Autocomplete for `AlertRule#unit_size_filter`.** It's a free-text
    string column today, an alert rule for "10x10" won't match a unit
    listed as "10 x 10" or "10X10" unless the text is exact. Populating a
    dropdown from `Unit.distinct.pluck(:size)` (sizes actually seen by the
    crawler) instead of a free-text field would remove that whole class
    of silently-broken alert rules.

17. **Price-per-square-foot as a sortable column.** `Unit` already has
    `sqft` and `monthly_price`; a 5x5 and a 10x20 aren't directly
    comparable by price alone, price/sqft is the number that actually
    lets someone compare across sizes.

18. **Pick-any-two crawl comparison.** The existing price-history and
    "what changed" ideas (1, 5) both assume adjacent crawls. A dedicated
    view for picking any two `CrawlRun`s by date and diffing them (not
    just consecutive ones) would answer "how much has this changed since
    I started tracking it" months later, not just "what changed since
    yesterday."

19. **Auto-export before history purge.** `history_keep_months` already
    drives an automatic purge of old `Unit`/`CrawlRun` records in
    `CrawlJob` (see `BUILD_LOG.md`'s note on this). Right now that data is
    just gone once it ages out. Running the existing `build_csv` export
    once against the batch about to be purged, and saving the file rather
    than discarding the rows, would make the retention setting a rollup
    instead of a deletion.
