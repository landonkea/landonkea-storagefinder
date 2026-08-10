# =============================================================================
# MIGRATION: Create All Tables
# =============================================================================
# A migration is a set of instructions that changes the database structure.
# Rails runs migrations in order (sorted by the timestamp in the filename).
#
# Run this with: rails db:migrate
# Undo it with:  rails db:rollback
# =============================================================================

# `class CreateAllTables < ActiveRecord::Migration[7.1]` defines a new Ruby
# class named CreateAllTables. The `<` means this class INHERITS from
# `ActiveRecord::Migration[7.1]`, it reuses all the migration machinery
# (running, rolling back, tracking "have I already run?" in the database)
# that Rails provides, versioned to behave like Rails 7.1 so future Rails
# upgrades don't silently change how this specific migration executes.
# Every migration file defines one class like this. The `end` at the very
# bottom of the file closes this class definition.
class CreateAllTables < ActiveRecord::Migration[7.1]
  # `def change` defines a single method named "change", this is the
  # standard entry point Rails looks for in a migration. Because every
  # statement inside it (create_table, add_index, etc.) is one Rails already
  # knows how to reverse automatically, Rails can run this same method
  # forwards for `db:migrate` and backwards for `db:rollback` without you
  # writing separate "up" and "down" methods. The matching `end` near the
  # bottom of the file (just above the class's closing `end`) closes this
  # method.
  def change
    # -------------------------------------------------------------------------
    # FACILITIES TABLE
    # -------------------------------------------------------------------------
    # `create_table :facilities` creates a new database table (think: a
    # spreadsheet with named columns) named "facilities", this will hold
    # one row per physical self-storage location. `:facilities` is a Ruby
    # SYMBOL (a lightweight, immutable name/label, written with a leading
    # colon), Rails methods like this commonly accept symbols for table and
    # column names instead of plain strings. `do |t|` opens a block where
    # `t` is a table-definition helper object; every `t.something` line
    # below adds one column to the table. The matching `end` a few lines
    # down closes this `create_table` call.
    create_table :facilities do |t|
      # `t.string  :company` adds a text column named "company" (holds
      # short text, like a name), the storage company operating this
      # facility (e.g. "Public Storage"). `null: false` means the database
      # will reject any row that doesn't supply a value, this column is
      # required. The extra spaces before `:company` are just manual
      # alignment so the column names line up visually; they have no effect
      # on the code.
      t.string  :company,       null: false
      # Text column for the facility's own name/label, also required.
      t.string  :name,          null: false
      # Text column for the street address, required.
      t.string  :address,       null: false
      # Text column for the city, required.
      t.string  :city,          null: false
      # Text column for the state, required.
      t.string  :state,         null: false
      # Text column for the ZIP/postal code, required.
      t.string  :zip,           null: false
      # Text column for a contact phone number. No `null: false` here, so
      # this column is OPTIONAL, rows can be saved with this left blank
      # (nil), unlike the required columns above.
      t.string  :phone
      # `t.float` adds a column that stores a floating-point (decimal)
      # number, used here for the facility's geographic latitude
      # coordinate. Optional (no null: false).
      t.float   :latitude
      # Floating-point column for the facility's geographic longitude
      # coordinate. Optional.
      t.float   :longitude
      # Floating-point column recording how far this facility is (in miles)
      # from whatever location was searched. Optional, only meaningful
      # after a distance calculation has run.
      t.float   :distance_miles
      # Text column for the URL of this facility's page on the storage
      # company's website. Optional.
      t.string  :facility_url
      # Text column for an identifier the storage company itself uses for
      # this facility (e.g. a store number from their own system), used
      # later (see the 2026 migration) to detect duplicate facilities.
      # Optional, since not every company's site exposes one.
      t.string  :external_id

      # `t.timestamps` is a Rails shortcut that adds TWO columns in one
      # line: "created_at" and "updated_at", both datetime columns that
      # Rails automatically fills in and keeps up to date whenever a row is
      # inserted or changed, you never set these yourself.
      t.timestamps  # Adds created_at and updated_at automatically
    end
    # This `end` closes the `create_table :facilities do |t|` block above,
    # every column for the facilities table has now been described.

    # Indexes for facility lookups
    # `add_index` creates a database INDEX on an existing table, a lookup
    # structure similar to a book's index, letting queries jump straight to
    # matching rows instead of scanning the whole table. This one speeds up
    # lookups/filters by "company".
    add_index :facilities, :company
    # Index speeding up lookups/filters by "city".
    add_index :facilities, :city
    # Index speeding up lookups/filters by "zip".
    add_index :facilities, :zip
    # A single index built across TWO columns at once, `[ :latitude,
    # :longitude ]` is a Ruby array literal (a list) naming both columns.
    # This speeds up queries that filter/sort using both coordinates
    # together, such as "find facilities within this bounding box."
    add_index :facilities, [ :latitude, :longitude ]

    # -------------------------------------------------------------------------
    # CRAWL RUNS TABLE
    # -------------------------------------------------------------------------
    # Must be created BEFORE units because units reference crawl_runs
    # Starts a new table, "crawl_runs", one row per time the app ran a
    # crawl (an automated search across storage company websites).
    create_table :crawl_runs do |t|
      # Text column recording the city name that was searched. Optional (no
      # null: false), for example it might not be set until the crawl
      # actually starts.
      t.string   :search_city
      # Floating-point column for the latitude of the searched location.
      t.float    :search_lat
      # Floating-point column for the longitude of the searched location.
      t.float    :search_lng
      # Whole-number column for how wide a radius (in miles) was searched.
      t.integer  :search_radius_miles
      # Text column tracking this crawl's current status (e.g. "pending",
      # "running", "completed", "failed"). `default: "pending"` means if no
      # value is explicitly given when a row is created, the database fills
      # in "pending" automatically.
      t.string   :status,            default: "pending"
      # `t.text` adds a column for longer free-form text than `t.string`
      # typically allows, used here to store an error message if the crawl
      # failed. Optional.
      t.text     :error_message
      # Whole-number column counting how many facilities this crawl found.
      # `default: 0` means new rows start at zero until updated.
      t.integer  :facilities_found,  default: 0
      # Whole-number column counting how many storage units this crawl
      # found, defaulting to 0.
      t.integer  :units_found,       default: 0
      # Whole-number column counting how many companies were successfully
      # crawled, defaulting to 0.
      t.integer  :companies_crawled, default: 0
      # Whole-number column counting how many companies failed to crawl,
      # defaulting to 0.
      t.integer  :companies_failed,  default: 0
      # `t.json` adds a column that stores structured JSON data (lists/
      # objects) directly, rather than one plain string, used here to
      # record which companies were included in this crawl run. Optional.
      t.json     :companies_included
      # JSON column recording whatever filter options were applied for this
      # crawl (e.g. size/price filters). Optional.
      t.json     :filter_options
      # Datetime column recording when the crawl actually started running.
      # Optional, nil until the crawl begins.
      t.datetime :started_at
      # Datetime column recording when the crawl finished. Optional, nil
      # until the crawl completes.
      t.datetime :completed_at
      # Floating-point column recording how long the crawl took, in
      # seconds. Optional, only set once the crawl finishes.
      t.float    :duration_seconds

      # Adds the automatic created_at/updated_at timestamp columns, same as
      # in the facilities table above.
      t.timestamps
    end
    # Closes the `create_table :crawl_runs do |t|` block above.

    # Index speeding up lookups/filters by crawl "status" (e.g. finding all
    # currently-running crawls).
    add_index :crawl_runs, :status
    # Index speeding up sorting/filtering crawl runs by when they were
    # created (e.g. showing the most recent crawls first).
    add_index :crawl_runs, :created_at

    # -------------------------------------------------------------------------
    # UNITS TABLE
    # -------------------------------------------------------------------------
    # Starts a new table, "units", one row per individual storage unit
    # (e.g. a specific 10x10 unit) found at a facility during a crawl.
    create_table :units do |t|
      # `t.references :facility` is a Rails shortcut that adds a
      # "facility_id" whole-number column, linking each unit row back to
      # the one row in the "facilities" table it belongs to. `null: false`
      # means every unit MUST belong to a facility. `foreign_key: true`
      # tells the DATABASE ITSELF (not just Rails) to enforce this link, a
      # FOREIGN KEY is a database-level rule that a value in one table's
      # column must match an existing row's id in another table; it blocks
      # inserting a unit that points at a facility_id that doesn't actually
      # exist, and by default blocks deleting a facility that still has
      # units pointing at it. The inline comment explains the same thing
      # concisely.
      t.references :facility,    null: false, foreign_key: true   # facility_id column + foreign key
      # Same pattern as above, but linking each unit to the "crawl_runs"
      # table via a new "crawl_run_id" column, records which crawl run
      # discovered this unit. Also required and foreign-key-enforced.
      t.references :crawl_run,   null: false, foreign_key: true   # crawl_run_id column + foreign key
      # Text column for the unit's size label (e.g. "10x10"), required.
      t.string   :size,          null: false
      # Whole-number column for the unit's width in feet. Optional.
      t.integer  :width_ft
      # Whole-number column for the unit's depth in feet. Optional.
      t.integer  :depth_ft
      # Whole-number column for the unit's total square footage. Optional.
      t.integer  :sqft
      # `t.decimal` adds a column that stores an EXACT decimal number
      # (unlike `t.float`, which can introduce tiny rounding errors), the
      # right choice for money values. `precision: 8, scale: 2` means up to
      # 8 total digits, with 2 of them after the decimal point (so values
      # up to 999999.99). Used here for the regular monthly rental price.
      # Optional.
      t.decimal  :monthly_price,     precision: 8, scale: 2
      # Decimal column (same precision/scale rules) for a discounted "web
      # special" price, if the company advertises one. Optional.
      t.decimal  :web_special_price, precision: 8, scale: 2
      # Text column for any fine-print note about the web special (e.g.
      # "first month free"). Optional.
      t.string   :web_special_note
      # Decimal column for a one-time administrative/setup fee. Optional.
      t.decimal  :admin_fee,         precision: 8, scale: 2
      # Text column for a note about required insurance. Optional.
      t.string   :insurance_note
      # `t.boolean` adds a true/false column. This one records whether the
      # unit is climate-controlled. `default: false` means new rows start
      # as false unless explicitly set otherwise.
      t.boolean  :climate_controlled, default: false
      # Boolean column recording whether the unit is currently available to
      # rent. `default: true`, units are assumed available unless marked
      # otherwise.
      t.boolean  :available,          default: true
      # Boolean column recording whether the unit has drive-up access,
      # defaulting to false.
      t.boolean  :drive_up,           default: false
      # Boolean column recording whether the unit is indoors, defaulting to
      # true.
      t.boolean  :indoor,             default: true
      # Text column describing the unit type (e.g. "self-storage",
      # "parking", "wine storage"). Optional.
      t.string   :unit_type
      # Text column for a URL where this specific unit can be booked.
      # Optional.
      t.string   :booking_url
      # Datetime column recording exactly when this unit's data was
      # collected/scraped. `null: false` means this is always required,
      # every unit row must record when its information was gathered.
      t.datetime :collected_at,  null: false

      # Adds the automatic created_at/updated_at timestamp columns.
      t.timestamps
    end
    # Closes the `create_table :units do |t|` block above.

    # Index speeding up lookups/filters by unit "size".
    add_index :units, :size
    # Index speeding up lookups/sorting by "monthly_price" (e.g. sorting
    # search results cheapest-first).
    add_index :units, :monthly_price
    # Index speeding up filtering by whether a unit is climate-controlled.
    add_index :units, :climate_controlled
    # Index speeding up filtering by whether a unit is currently available.
    add_index :units, :available
    # Index speeding up sorting/filtering units by when their data was
    # collected.
    add_index :units, :collected_at

    # -------------------------------------------------------------------------
    # CRAWL LOG ENTRIES TABLE
    # -------------------------------------------------------------------------
    # Starts a new table, "crawl_log_entries", one row per log message
    # produced while a crawl runs, useful for debugging failed crawls.
    create_table :crawl_log_entries do |t|
      # Links each log entry to the crawl run it belongs to, via a
      # "crawl_run_id" column. Required, and database-enforced via a
      # foreign key (see the fuller explanation on the units table above).
      t.references :crawl_run, null: false, foreign_key: true
      # Text column for which storage company this log entry concerns.
      # Required.
      t.string   :company,     null: false
      # Text column for the URL being processed when this log entry was
      # produced. Optional.
      t.string   :url
      # Text column for the log severity level (e.g. "info", "warning",
      # "error"). `default: "info"` means entries are informational unless
      # marked otherwise.
      t.string   :level,       default: "info"
      # Longer free-form text column holding the actual log message.
      # Required, every log entry must have a message.
      t.text     :message,     null: false
      # Whole-number column counting how many times this action was
      # retried, defaulting to 0.
      t.integer  :retry_count, default: 0
      # Boolean column recording whether the logged action ultimately
      # succeeded. No default given, so it starts as nil (meaning
      # "unknown/not applicable") unless explicitly set true or false.
      t.boolean  :success

      # Adds the automatic created_at/updated_at timestamp columns.
      t.timestamps
    end
    # Closes the `create_table :crawl_log_entries do |t|` block above.

    # Index speeding up lookups/filters by "company" on the log entries.
    add_index :crawl_log_entries, :company

    # -------------------------------------------------------------------------
    # ALERT RULES TABLE
    # -------------------------------------------------------------------------
    # Starts a new table, "alert_rules", one row per user-defined rule for
    # when to send a notification (e.g. "alert me if a 10x10 unit drops
    # below $80/month").
    create_table :alert_rules do |t|
      # Text column for a human-readable name for this rule. Required.
      t.string   :name,                null: false
      # Text column identifying what kind of condition triggers this rule
      # (e.g. "price_drop", "new_unit"). Required.
      t.string   :trigger_type,        null: false
      # Decimal column (money-safe, see explanation on units table above)
      # for the price threshold that triggers this rule. Optional, not
      # every trigger type needs a price.
      t.decimal  :threshold_price,     precision: 8, scale: 2
      # Text column optionally restricting this rule to a specific unit
      # size. Optional.
      t.string   :unit_size_filter
      # Text column optionally restricting this rule to a specific storage
      # company. Optional.
      t.string   :company_filter
      # Boolean column: whether this rule should send an email when
      # triggered. Defaults to false (off).
      t.boolean  :email_enabled,       default: false
      # Text column for the email address to notify. Optional.
      t.string   :email_address
      # Boolean column: whether this rule should post to Discord when
      # triggered. Defaults to false.
      t.boolean  :discord_enabled,     default: false
      # Text column for the Discord webhook URL to post to. Optional.
      t.string   :discord_webhook_url
      # Boolean column: whether this rule should send an SMS text message
      # when triggered. Defaults to false.
      t.boolean  :sms_enabled,         default: false
      # Text column for the phone number to text. Optional.
      t.string   :sms_phone_number
      # Boolean column: whether this rule is currently active/enabled at
      # all. Defaults to true, new rules start turned on.
      t.boolean  :active,              default: true
      # Datetime column recording the last time this rule actually fired.
      # Optional, nil until it triggers for the first time.
      t.datetime :last_triggered_at

      # Adds the automatic created_at/updated_at timestamp columns.
      t.timestamps
    end
    # Closes the `create_table :alert_rules do |t|` block above. Note there
    # are no `add_index` calls for this table, no extra lookup indexes
    # were considered necessary for alert rules.

    # -------------------------------------------------------------------------
    # SETTINGS TABLE
    # -------------------------------------------------------------------------
    # Starts a new table, "settings", one row per configurable application
    # setting shown on the Settings page (see db/seeds.rb, which populates
    # this table with the actual default settings).
    create_table :settings do |t|
      # Text column for the setting's unique identifier/name (e.g.
      # "crawl_default_radius_miles"). Required.
      t.string :key,        null: false
      # Longer free-form text column for the setting's current value,
      # stored as text regardless of the setting's logical type (numbers
      # and booleans are stored as their text representation, e.g. "true"
      # or "100"). Optional.
      t.text   :value
      # Text column grouping settings for display (e.g. "crawl", "email").
      # Optional.
      t.string :category
      # Text column for the human-readable label shown on the Settings
      # page. Optional.
      t.string :label
      # Text column naming which HTML input type to render for this setting
      # (e.g. "text", "number", "boolean", "password"). `default: "text"`
      # means settings render as a plain text box unless told otherwise.
      t.string :input_type, default: "text"

      # Adds the automatic created_at/updated_at timestamp columns.
      t.timestamps
    end
    # Closes the `create_table :settings do |t|` block above.

    # Key must be unique, prevents duplicate settings entries
    # `add_index :settings, :key, unique: true` builds an index on "key",
    # and `unique: true` makes it a UNIQUE INDEX, the database itself will
    # reject any attempt to insert a second row with a "key" value that
    # already exists, guaranteeing every setting name appears at most once.
    add_index :settings, :key, unique: true
  end
  # This `end` closes the `def change` method opened near the top of the
  # file, every table this migration creates has now been fully described.
end
# This final `end` closes the `class CreateAllTables < ActiveRecord::Migration[7.1]`
# class definition opened at the top of the file.
