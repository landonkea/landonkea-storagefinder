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

ActiveRecord::Schema[8.1].define(version: 2026_07_18_200000) do
  create_table "alert_rules", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "company_filter"
    t.datetime "created_at", null: false
    t.boolean "discord_enabled", default: false
    t.string "discord_webhook_url"
    t.string "email_address"
    t.boolean "email_enabled", default: false
    t.datetime "last_triggered_at"
    t.string "name", null: false
    t.boolean "sms_enabled", default: false
    t.string "sms_phone_number"
    t.decimal "threshold_price", precision: 8, scale: 2
    t.string "trigger_type", null: false
    t.string "unit_size_filter"
    t.datetime "updated_at", null: false
  end

  create_table "crawl_log_entries", force: :cascade do |t|
    t.string "company", null: false
    t.integer "crawl_run_id", null: false
    t.datetime "created_at", null: false
    t.string "level", default: "info"
    t.text "message", null: false
    t.integer "retry_count", default: 0
    t.boolean "success"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["company"], name: "index_crawl_log_entries_on_company"
    t.index ["crawl_run_id"], name: "index_crawl_log_entries_on_crawl_run_id"
  end

  create_table "crawl_runs", force: :cascade do |t|
    t.integer "companies_crawled", default: 0
    t.integer "companies_failed", default: 0
    t.json "companies_included"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.float "duration_seconds"
    t.text "error_message"
    t.integer "facilities_found", default: 0
    t.json "filter_options"
    t.string "search_city"
    t.float "search_lat"
    t.float "search_lng"
    t.integer "search_radius_miles"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.integer "units_found", default: 0
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_crawl_runs_on_created_at"
    t.index ["status"], name: "index_crawl_runs_on_status"
  end

  create_table "facilities", force: :cascade do |t|
    t.string "address", null: false
    t.string "city", null: false
    t.string "company", null: false
    t.datetime "created_at", null: false
    t.float "distance_miles"
    t.string "external_id"
    t.string "facility_url"
    t.float "latitude"
    t.float "longitude"
    t.string "name", null: false
    t.string "phone"
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.string "zip", null: false
    t.index ["city"], name: "index_facilities_on_city"
    t.index ["company", "address", "city", "state"], name: "index_facilities_on_company_and_address_uniq", unique: true, where: "external_id IS NULL"
    t.index ["company", "external_id"], name: "index_facilities_on_company_and_external_id_uniq", unique: true, where: "external_id IS NOT NULL"
    t.index ["company"], name: "index_facilities_on_company"
    t.index ["latitude", "longitude"], name: "index_facilities_on_latitude_and_longitude"
    t.index ["zip"], name: "index_facilities_on_zip"
  end

  create_table "settings", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "input_type", default: "text"
    t.string "key", null: false
    t.string "label"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "units", force: :cascade do |t|
    t.decimal "admin_fee", precision: 8, scale: 2
    t.boolean "available", default: true
    t.string "booking_url"
    t.boolean "climate_controlled", default: false
    t.datetime "collected_at", null: false
    t.integer "crawl_run_id", null: false
    t.datetime "created_at", null: false
    t.integer "depth_ft"
    t.boolean "drive_up", default: false
    t.integer "facility_id", null: false
    t.boolean "indoor", default: true
    t.string "insurance_note"
    t.decimal "monthly_price", precision: 8, scale: 2
    t.string "size", null: false
    t.integer "sqft"
    t.string "unit_type"
    t.datetime "updated_at", null: false
    t.string "web_special_note"
    t.decimal "web_special_price", precision: 8, scale: 2
    t.integer "width_ft"
    t.index ["available"], name: "index_units_on_available"
    t.index ["climate_controlled"], name: "index_units_on_climate_controlled"
    t.index ["collected_at"], name: "index_units_on_collected_at"
    t.index ["crawl_run_id"], name: "index_units_on_crawl_run_id"
    t.index ["facility_id"], name: "index_units_on_facility_id"
    t.index ["monthly_price"], name: "index_units_on_monthly_price"
    t.index ["size"], name: "index_units_on_size"
  end

  add_foreign_key "crawl_log_entries", "crawl_runs"
  add_foreign_key "units", "crawl_runs"
  add_foreign_key "units", "facilities"
end
