# =============================================================================
# MIGRATION: Create All Tables
# =============================================================================
# A migration is a set of instructions that changes the database structure.
# Rails runs migrations in order (sorted by the timestamp in the filename).
#
# Run this with: rails db:migrate
# Undo it with:  rails db:rollback
# =============================================================================

class CreateAllTables < ActiveRecord::Migration[7.1]
  def change
    # -------------------------------------------------------------------------
    # FACILITIES TABLE
    # -------------------------------------------------------------------------
    create_table :facilities do |t|
      t.string  :company,       null: false
      t.string  :name,          null: false
      t.string  :address,       null: false
      t.string  :city,          null: false
      t.string  :state,         null: false
      t.string  :zip,           null: false
      t.string  :phone
      t.float   :latitude
      t.float   :longitude
      t.float   :distance_miles
      t.string  :facility_url
      t.string  :external_id

      t.timestamps  # Adds created_at and updated_at automatically
    end

    # Indexes for facility lookups
    add_index :facilities, :company
    add_index :facilities, :city
    add_index :facilities, :zip
    add_index :facilities, [ :latitude, :longitude ]

    # -------------------------------------------------------------------------
    # CRAWL RUNS TABLE
    # -------------------------------------------------------------------------
    # Must be created BEFORE units because units reference crawl_runs
    create_table :crawl_runs do |t|
      t.string   :search_city
      t.float    :search_lat
      t.float    :search_lng
      t.integer  :search_radius_miles
      t.string   :status,            default: "pending"
      t.text     :error_message
      t.integer  :facilities_found,  default: 0
      t.integer  :units_found,       default: 0
      t.integer  :companies_crawled, default: 0
      t.integer  :companies_failed,  default: 0
      t.json     :companies_included
      t.json     :filter_options
      t.datetime :started_at
      t.datetime :completed_at
      t.float    :duration_seconds

      t.timestamps
    end

    add_index :crawl_runs, :status
    add_index :crawl_runs, :created_at

    # -------------------------------------------------------------------------
    # UNITS TABLE
    # -------------------------------------------------------------------------
    create_table :units do |t|
      t.references :facility,    null: false, foreign_key: true   # facility_id column + foreign key
      t.references :crawl_run,   null: false, foreign_key: true   # crawl_run_id column + foreign key
      t.string   :size,          null: false
      t.integer  :width_ft
      t.integer  :depth_ft
      t.integer  :sqft
      t.decimal  :monthly_price,     precision: 8, scale: 2
      t.decimal  :web_special_price, precision: 8, scale: 2
      t.string   :web_special_note
      t.decimal  :admin_fee,         precision: 8, scale: 2
      t.string   :insurance_note
      t.boolean  :climate_controlled, default: false
      t.boolean  :available,          default: true
      t.boolean  :drive_up,           default: false
      t.boolean  :indoor,             default: true
      t.string   :unit_type
      t.string   :booking_url
      t.datetime :collected_at,  null: false

      t.timestamps
    end

    add_index :units, :size
    add_index :units, :monthly_price
    add_index :units, :climate_controlled
    add_index :units, :available
    add_index :units, :collected_at

    # -------------------------------------------------------------------------
    # CRAWL LOG ENTRIES TABLE
    # -------------------------------------------------------------------------
    create_table :crawl_log_entries do |t|
      t.references :crawl_run, null: false, foreign_key: true
      t.string   :company,     null: false
      t.string   :url
      t.string   :level,       default: "info"
      t.text     :message,     null: false
      t.integer  :retry_count, default: 0
      t.boolean  :success

      t.timestamps
    end

    add_index :crawl_log_entries, :company

    # -------------------------------------------------------------------------
    # ALERT RULES TABLE
    # -------------------------------------------------------------------------
    create_table :alert_rules do |t|
      t.string   :name,                null: false
      t.string   :trigger_type,        null: false
      t.decimal  :threshold_price,     precision: 8, scale: 2
      t.string   :unit_size_filter
      t.string   :company_filter
      t.boolean  :email_enabled,       default: false
      t.string   :email_address
      t.boolean  :discord_enabled,     default: false
      t.string   :discord_webhook_url
      t.boolean  :sms_enabled,         default: false
      t.string   :sms_phone_number
      t.boolean  :active,              default: true
      t.datetime :last_triggered_at

      t.timestamps
    end

    # -------------------------------------------------------------------------
    # SETTINGS TABLE
    # -------------------------------------------------------------------------
    create_table :settings do |t|
      t.string :key,        null: false
      t.text   :value
      t.string :category
      t.string :label
      t.string :input_type, default: "text"

      t.timestamps
    end

    # Key must be unique — prevents duplicate settings entries
    add_index :settings, :key, unique: true
  end
end
