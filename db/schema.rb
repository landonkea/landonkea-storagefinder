# =============================================================================
# READ THIS FIRST: this file is auto-generated and gets OVERWRITTEN.
# =============================================================================
# Every comment in this file — including this one — will be SILENTLY LOST
# the next time anyone runs `bin/rails db:migrate` or
# `bin/rails db:schema:load`. That is expected and fine, not a bug.
#
# Here's why: this file is not something a person writes by hand. It's a
# generated SNAPSHOT of the database structure, produced automatically by
# replaying every file in db/migrate/ in order. Each time a migration runs,
# Rails regenerates this entire file from scratch to match the new
# structure, and dumps it back out as plain Ruby code (the same code you're
# reading now). So the *real*, permanent source of truth for "what does this
# database look like" is the migration files in db/migrate/ (see
# db/migrate/20240101000001_create_all_tables.rb and
# db/migrate/20260718200000_add_facility_uniqueness_indexes.rb) — this file
# is just their combined, up-to-date result, cached here so a brand-new
# database can be built in one fast step instead of re-running every
# migration one by one.
#
# The comments below explain the file thoroughly anyway (per the commenting
# pass this file went through), but keep that caveat in mind: if you want a
# comment to survive long-term, it needs to live in a migration file, not
# here.
# =============================================================================
#
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

# `ActiveRecord::Schema[8.1]` says "build this schema using the rules/syntax
# of ActiveRecord as they existed in Rails version 8.1" — pinning a version
# number here means later Rails upgrades won't silently change how this file
# is interpreted, even years from now. `.define(version: ...) do ... end`
# starts the block listing every table in the app's MAIN database (as
# opposed to the separate cable/cache/queue databases, which each have their
# own schema files — see db/cable_schema.rb, db/cache_schema.rb,
# db/queue_schema.rb). `version: 2026_07_18_200000` records the TIMESTAMP
# (from a migration's filename, with underscores just for human readability
# — Ruby ignores underscores inside number literals) of the most recent
# migration that has been applied — here, matching
# db/migrate/20260718200000_add_facility_uniqueness_indexes.rb. This is how
# Rails knows which migrations still need to run on `db:migrate` versus
# which are already reflected in the database. The matching `end` at the
# very bottom of this file closes this `.define do` block.
ActiveRecord::Schema[8.1].define(version: 2026_08_03_000000) do
  # `create_table "alert_rules"` defines a database table (think: a
  # spreadsheet with named columns) named "alert_rules" — one row per
  # user-defined notification rule (see the migration
  # db/migrate/20240101000001_create_all_tables.rb for the original,
  # narrated version of how this table came to exist). `force: :cascade`
  # tells Rails "if a table with this name already exists, drop it first
  # and recreate it" — safe here since this file is only used to build a
  # database from nothing. `do |t|` opens a block where `t` is a
  # table-definition helper; each `t.something` line adds one column. Note:
  # unlike the migration file, columns here are listed in ALPHABETICAL
  # ORDER rather than the order they were originally added — that's simply
  # how Rails' schema dumper formats this generated file, not a meaningful
  # difference.
  create_table "alert_rules", force: :cascade do |t|
    # `t.boolean "active"` adds a true/false column recording whether this
    # rule is currently turned on. `default: true` means new rows start
    # active unless set otherwise.
    t.boolean "active", default: true
    # `t.string "company_filter"` adds a text column optionally restricting
    # this rule to one storage company. No `default:`/`null: false` shown,
    # so it's optional and can be left blank (nil).
    t.string "company_filter"
    # `t.integer "cooldown_minutes"` adds a "quiet hours" window (see the
    # migration db/migrate/20260803000000_add_cooldown_minutes_to_alert_rules.rb)
    # — once this rule fires, it won't fire again until this many minutes
    # have passed, even if its trigger condition still matches on a later
    # crawl. `default: 0` means "no cooldown" (fire every time it matches,
    # today's original behavior) unless a rule explicitly opts in to a
    # longer window. `null: false` — every row always has SOME integer
    # value here, guaranteed by that same default.
    t.integer "cooldown_minutes", default: 0, null: false
    # `t.datetime "created_at"` adds a timestamp column recording when this
    # row was created. `null: false` means the database requires every row
    # to have this value — it's one of the automatic columns Rails' earlier
    # `t.timestamps` shortcut (used in the migration) expands into.
    t.datetime "created_at", null: false
    # Boolean column: whether this rule posts to Discord when triggered,
    # defaulting to false.
    t.boolean "discord_enabled", default: false
    # Text column for the Discord webhook URL to notify. Optional.
    t.string "discord_webhook_url"
    # Text column for the email address to notify. Optional.
    t.string "email_address"
    # Boolean column: whether this rule sends email when triggered,
    # defaulting to false.
    t.boolean "email_enabled", default: false
    # Datetime column recording the last time this rule fired. Optional —
    # nil until it triggers once.
    t.datetime "last_triggered_at"
    # Text column for the rule's human-readable name. `null: false` means
    # required.
    t.string "name", null: false
    # Boolean column: whether this rule sends SMS when triggered,
    # defaulting to false.
    t.boolean "sms_enabled", default: false
    # Text column for the phone number to text. Optional.
    t.string "sms_phone_number"
    # `t.decimal "threshold_price"` adds a column that stores an EXACT
    # decimal number (unlike a float, which can introduce tiny rounding
    # errors) — the right choice for money. `precision: 8, scale: 2` means
    # up to 8 total digits, 2 after the decimal point (values up to
    # 999999.99). Optional.
    t.decimal "threshold_price", precision: 8, scale: 2
    # Text column identifying what kind of condition triggers this rule.
    # `null: false` means required.
    t.string "trigger_type", null: false
    # Text column optionally restricting this rule to one unit size.
    # Optional.
    t.string "unit_size_filter"
    # Timestamp column recording when this row was last updated. `null:
    # false` means required — like created_at, this comes from
    # `t.timestamps` in the original migration.
    t.datetime "updated_at", null: false
  end
  # Closes the `create_table "alert_rules" do |t|` block above. Note this
  # table has no `t.index` lines and no add_index calls elsewhere in this
  # file — matching the original migration, which also added no extra
  # lookup indexes for alert_rules.

  # Table holding one row per log message produced while a crawl runs.
  create_table "crawl_log_entries", force: :cascade do |t|
    # Text column naming which storage company this log entry concerns.
    # Required.
    t.string "company", null: false
    # `t.integer "crawl_run_id"` adds a whole-number column linking this
    # log entry back to the crawl run it belongs to. This is the plain
    # column that Rails' `t.references :crawl_run, foreign_key: true` (used
    # in the migration) expands into once dumped as a schema — `null:
    # false` means required.
    t.integer "crawl_run_id", null: false
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Text column for the log severity level. `default: "info"` means
    # entries default to informational.
    t.string "level", default: "info"
    # `t.text "message"` adds a column for longer free-form text than
    # `t.string` typically allows — holds the actual log message. Required.
    t.text "message", null: false
    # Whole-number column counting retries, defaulting to 0.
    t.integer "retry_count", default: 0
    # Boolean column recording whether the logged action succeeded. No
    # default, so it can be nil ("unknown") as well as true/false.
    t.boolean "success"
    # Timestamp column recording when this row was last updated. Required.
    t.datetime "updated_at", null: false
    # Text column for the URL being processed at the time of this log
    # entry. Optional.
    t.string "url"
    # Index speeding up lookups/filters by "company".
    t.index ["company"], name: "index_crawl_log_entries_on_company"
    # Index speeding up lookups of all log entries for a given crawl run —
    # this is the index that Rails' `foreign_key: true` option
    # automatically creates alongside the foreign key itself, so lookups by
    # crawl_run_id stay fast.
    t.index ["crawl_run_id"], name: "index_crawl_log_entries_on_crawl_run_id"
  end
  # Closes the `create_table "crawl_log_entries" do |t|` block above.

  # Table holding one row per time the app ran a crawl (an automated search
  # across storage company websites).
  create_table "crawl_runs", force: :cascade do |t|
    # Whole-number column counting successfully crawled companies,
    # defaulting to 0.
    t.integer "companies_crawled", default: 0
    # Whole-number column counting companies that failed to crawl,
    # defaulting to 0.
    t.integer "companies_failed", default: 0
    # `t.json "companies_included"` adds a column storing structured JSON
    # data directly, rather than one plain string — records which companies
    # were part of this crawl. Optional.
    t.json "companies_included"
    # Datetime column recording when the crawl finished. Optional — nil
    # until completion.
    t.datetime "completed_at"
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Floating-point column recording how long the crawl took, in seconds.
    # Optional.
    t.float "duration_seconds"
    # Longer free-form text column for an error message if the crawl
    # failed. Optional.
    t.text "error_message"
    # Whole-number column counting facilities found, defaulting to 0.
    t.integer "facilities_found", default: 0
    # JSON column recording whatever filter options were applied. Optional.
    t.json "filter_options"
    # Text column recording the searched city name. Optional.
    t.string "search_city"
    # Floating-point column for the searched location's latitude. Optional.
    t.float "search_lat"
    # Floating-point column for the searched location's longitude.
    # Optional.
    t.float "search_lng"
    # Whole-number column for the search radius in miles. Optional.
    t.integer "search_radius_miles"
    # Datetime column recording when the crawl started. Optional — nil
    # until it begins.
    t.datetime "started_at"
    # Text column tracking the crawl's current status. `default: "pending"`
    # means new rows start pending.
    t.string "status", default: "pending"
    # Whole-number column counting units found, defaulting to 0.
    t.integer "units_found", default: 0
    # Timestamp column recording when this row was last updated. Required.
    t.datetime "updated_at", null: false
    # Index speeding up sorting/filtering crawl runs by when they were
    # created.
    t.index ["created_at"], name: "index_crawl_runs_on_created_at"
    # Index speeding up lookups/filters by crawl "status".
    t.index ["status"], name: "index_crawl_runs_on_status"
  end
  # Closes the `create_table "crawl_runs" do |t|` block above.

  # Table holding one row per physical self-storage facility location.
  create_table "facilities", force: :cascade do |t|
    # Text column for the street address. Required.
    t.string "address", null: false
    # Text column for the city. Required.
    t.string "city", null: false
    # Text column for the storage company operating this facility.
    # Required.
    t.string "company", null: false
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Floating-point column recording distance (in miles) from a searched
    # location. Optional.
    t.float "distance_miles"
    # Text column for an identifier the storage company uses internally for
    # this facility, when available. Optional — used together with
    # "company" below to detect duplicate facilities from the same company.
    t.string "external_id"
    # Text column for the URL of this facility's page on the company's
    # website. Optional.
    t.string "facility_url"
    # Floating-point column for the facility's latitude. Optional.
    t.float "latitude"
    # Floating-point column for the facility's longitude. Optional.
    t.float "longitude"
    # Text column for the facility's own name/label. Required.
    t.string "name", null: false
    # Text column for a contact phone number. Optional.
    t.string "phone"
    # Text column for the state. Required.
    t.string "state", null: false
    # Timestamp column recording when this row was last updated. Required.
    t.datetime "updated_at", null: false
    # Text column for the ZIP/postal code. Required.
    t.string "zip", null: false
    # Index speeding up lookups/filters by "city".
    t.index ["city"], name: "index_facilities_on_city"
    # A UNIQUE INDEX (see `unique: true`) across four columns together —
    # company, address, city, state. A unique index means the database
    # will reject inserting a second row with the exact same combination of
    # values across all of these columns at once. `where: "external_id IS
    # NULL"` makes this a PARTIAL index: the uniqueness rule only applies
    # to rows that have NO external_id set, which is exactly the
    # fallback-dedupe case described in
    # db/migrate/20260718200000_add_facility_uniqueness_indexes.rb (the
    # migration that added this index after the table already existed).
    t.index ["company", "address", "city", "state"], name: "index_facilities_on_company_and_address_uniq", unique: true, where: "external_id IS NULL"
    # A second unique, partial index — this one across (company,
    # external_id), only applied to rows WHERE "external_id IS NOT NULL".
    # Together with the index above, every facility row is covered by
    # exactly one of these two uniqueness rules, since a row either has an
    # external_id or it doesn't. This is the primary dedupe key when a
    # company's website exposes a stable per-location identifier.
    t.index ["company", "external_id"], name: "index_facilities_on_company_and_external_id_uniq", unique: true, where: "external_id IS NOT NULL"
    # A plain (non-unique) index on "company" alone, for fast filtering by
    # company regardless of the composite indexes above.
    t.index ["company"], name: "index_facilities_on_company"
    # Two-column index on (latitude, longitude) together, speeding up
    # geographic queries like "find facilities in this bounding box."
    t.index ["latitude", "longitude"], name: "index_facilities_on_latitude_and_longitude"
    # Index speeding up lookups/filters by "zip".
    t.index ["zip"], name: "index_facilities_on_zip"
  end
  # Closes the `create_table "facilities" do |t|` block above.

  # Table holding one row per configurable application setting (populated
  # with actual default rows by db/seeds.rb).
  create_table "settings", force: :cascade do |t|
    # Text column grouping settings for display purposes. Optional.
    t.string "category"
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Text column naming which HTML input type to render for this setting.
    # `default: "text"` means settings render as plain text boxes unless
    # told otherwise.
    t.string "input_type", default: "text"
    # Text column for the setting's unique identifier/name. Required.
    t.string "key", null: false
    # Text column for the human-readable label shown on the Settings page.
    # Optional.
    t.string "label"
    # Timestamp column recording when this row was last updated. Required.
    t.datetime "updated_at", null: false
    # Longer free-form text column for the setting's current value, stored
    # as text regardless of its logical type. Optional.
    t.text "value"
    # UNIQUE INDEX on "key" — the database rejects a second row with a
    # "key" that already exists, so every setting name appears at most
    # once.
    t.index ["key"], name: "index_settings_on_key", unique: true
  end
  # Closes the `create_table "settings" do |t|` block above.

  # Table holding one row per individual storage unit found at a facility
  # during a crawl.
  create_table "units", force: :cascade do |t|
    # Decimal column (money-safe, see explanation on "threshold_price"
    # above) for a one-time administrative/setup fee. Optional.
    t.decimal "admin_fee", precision: 8, scale: 2
    # Boolean column: whether the unit is currently available to rent.
    # `default: true` means units are assumed available unless marked
    # otherwise.
    t.boolean "available", default: true
    # Text column for a URL where this unit can be booked. Optional.
    t.string "booking_url"
    # Boolean column: whether the unit is climate-controlled, defaulting to
    # false.
    t.boolean "climate_controlled", default: false
    # Datetime column recording exactly when this unit's data was
    # collected/scraped. `null: false` means required.
    t.datetime "collected_at", null: false
    # Whole-number column linking this unit to the crawl run that found it
    # — the plain column form of `t.references :crawl_run, foreign_key:
    # true` from the original migration. Required.
    t.integer "crawl_run_id", null: false
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Whole-number column for the unit's depth in feet. Optional.
    t.integer "depth_ft"
    # Boolean column: whether the unit has drive-up access, defaulting to
    # false.
    t.boolean "drive_up", default: false
    # Whole-number column linking this unit to the facility it's located
    # at — the plain column form of `t.references :facility, foreign_key:
    # true` from the original migration. Required.
    t.integer "facility_id", null: false
    # Boolean column: whether the unit is indoors, defaulting to true.
    t.boolean "indoor", default: true
    # Text column for a note about required insurance. Optional.
    t.string "insurance_note"
    # Decimal column (money-safe) for the regular monthly rental price.
    # Optional.
    t.decimal "monthly_price", precision: 8, scale: 2
    # Text column for the unit's size label (e.g. "10x10"). Required.
    t.string "size", null: false
    # Whole-number column for the unit's total square footage. Optional.
    t.integer "sqft"
    # Text column describing the unit type (e.g. "self-storage",
    # "parking"). Optional.
    t.string "unit_type"
    # Timestamp column recording when this row was last updated. Required.
    t.datetime "updated_at", null: false
    # Text column for a note about a discounted "web special" price.
    # Optional.
    t.string "web_special_note"
    # Decimal column (money-safe) for the discounted "web special" price,
    # if advertised. Optional.
    t.decimal "web_special_price", precision: 8, scale: 2
    # Whole-number column for the unit's width in feet. Optional.
    t.integer "width_ft"
    # Index speeding up filtering by whether a unit is currently available.
    t.index ["available"], name: "index_units_on_available"
    # Index speeding up filtering by whether a unit is climate-controlled.
    t.index ["climate_controlled"], name: "index_units_on_climate_controlled"
    # Index speeding up sorting/filtering units by when their data was
    # collected.
    t.index ["collected_at"], name: "index_units_on_collected_at"
    # Index speeding up lookups of all units belonging to a given crawl run
    # — automatically created alongside the foreign key below.
    t.index ["crawl_run_id"], name: "index_units_on_crawl_run_id"
    # Index speeding up lookups of all units belonging to a given facility
    # — automatically created alongside the foreign key below.
    t.index ["facility_id"], name: "index_units_on_facility_id"
    # Index speeding up sorting/filtering by "monthly_price" (e.g. sorting
    # search results cheapest-first).
    t.index ["monthly_price"], name: "index_units_on_monthly_price"
    # Index speeding up lookups/filters by unit "size".
    t.index ["size"], name: "index_units_on_size"
  end
  # Closes the `create_table "units" do |t|` block above.

  # `add_foreign_key` adds a FOREIGN KEY constraint to an existing table — a
  # database-level rule that a column's value must match an existing row's
  # id in another table. Here it says every "crawl_log_entries" row's
  # crawl_run_id must point at a real row in "crawl_runs" (Rails infers the
  # referenced column name, "crawl_run_id", automatically from the target
  # table name "crawl_runs" since no explicit `column:` is given, unlike
  # the solid_queue foreign keys in db/queue_schema.rb which needed one).
  # This protects data integrity even if application code has a bug that
  # tries to insert a log entry for a crawl run that doesn't exist.
  add_foreign_key "crawl_log_entries", "crawl_runs"
  # Same pattern: every "units" row's crawl_run_id must point at a real row
  # in "crawl_runs".
  add_foreign_key "units", "crawl_runs"
  # Same pattern: every "units" row's facility_id must point at a real row
  # in "facilities".
  add_foreign_key "units", "facilities"
end
# This final `end` closes the `ActiveRecord::Schema[8.1].define(...) do`
# block opened at the top of the file — every table in the main database
# has now been fully described. Remember: this whole file, comments
# included, is regenerated automatically the next time a migration runs —
# see the note at the very top of the file.
