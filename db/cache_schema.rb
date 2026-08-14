# This file is a SCHEMA file, not a migration. A "schema" is a snapshot that
# describes the complete, current structure of a database (which tables
# exist, which columns each table has, which indexes speed up lookups) as of
# right now, as opposed to a migration, which describes a single CHANGE to
# apply. Rails can rebuild an empty database instantly by replaying this one
# file, instead of re-running every migration that ever existed one by one.
#
# This particular schema file is for a SEPARATE, secondary database used only
# by the "Solid Cache" gem (Rails' database-backed alternative to Redis/
# Memcached for the application's cache store, temporary data kept around
# to avoid redoing expensive work). Rails 8 apps can have multiple databases
# wired up (the app's main data, a cache store, a queue, a cable store, etc.)
# and each one gets its own schema file like this, that's why this lives in
# its own file instead of inside db/schema.rb.
#
# Like db/schema.rb, this file is auto-generated (by the solid_cache gem's
# own migrations), you would not hand-edit it in normal use. See the longer
# note in db/schema.rb for why comments added to auto-generated files like
# this one can get overwritten if the underlying migrations are ever re-run.

# `ActiveRecord::Schema[7.2]` says "build this schema using the rules/syntax
# of ActiveRecord as they existed in Rails version 7.2", pinning a version
# number here means later Rails upgrades won't silently change how this file
# is interpreted. (Note this is a different pinned version, 7.2, than the
# 7.1 used in db/cable_schema.rb/db/queue_schema.rb, each gem stamped its
# own schema file with whatever Rails version was installed when its
# migration last ran; this is normal and not something to "fix".)
# `.define(version: 1) do ... end` starts the block that lists every table
# for this database; `version: 1` records that only one migration (numbered
# 1) has ever been run against this specific database. The matching `end`
# at the very bottom of this file closes this `.define do` block.
ActiveRecord::Schema[7.2].define(version: 1) do
  # `create_table "solid_cache_entries"` defines a database table (think: a
  # spreadsheet with named columns) called "solid_cache_entries", every
  # cached value the app stores (via Rails.cache.write/read) becomes one row
  # here. `force: :cascade` tells Rails "if a table with this name already
  # exists, drop it first and recreate it from scratch", safe here because
  # this file is only used to build a database from nothing. `do |t|` opens
  # a block where `t` is a table-definition helper object, each
  # `t.something` line below adds one column. The matching `end` a few lines
  # from the bottom of this block closes this `create_table` call.
  create_table "solid_cache_entries", force: :cascade do |t|
    # `t.binary "key"` adds a column storing raw binary data, this holds
    # the cache key (the name you cache something under, e.g.
    # "user_42_profile"). `limit: 1024` caps it at 1024 bytes. `null: false`
    # means the database rejects any row that doesn't supply a key.
    t.binary "key", limit: 1024, null: false
    # `t.binary "value"` stores the actual cached data (whatever object was
    # cached, serialized to binary). `limit: 536870912` allows up to 512
    # megabytes (536,870,912 bytes) per cached entry. `null: false` means a
    # value is always required.
    t.binary "value", limit: 536870912, null: false
    # `t.datetime "created_at"` records when this cache entry was written,
    # used for cache eviction/expiry decisions. `null: false` means every
    # row must have this timestamp.
    t.datetime "created_at", null: false
    # `t.integer "key_hash"` stores a numeric hash (fixed-size fingerprint)
    # computed from the "key" column, so lookups can compare fast integers
    # instead of the full binary key each time. `limit: 8` means 8 bytes of
    # storage (a "bigint", for large hash values). `null: false` means it's
    # always required.
    t.integer "key_hash", limit: 8, null: false
    # `t.integer "byte_size"` records how many bytes the "value" column for
    # this row takes up, used so Solid Cache can track total cache size and
    # evict entries once storage limits are reached, without re-measuring
    # every row's actual data each time. `limit: 4` means 4 bytes of storage
    # (a regular 32-bit integer, plenty for a byte count). `null: false`
    # means it's always required.
    t.integer "byte_size", limit: 4, null: false
    # `t.index [...]` creates a database INDEX, a lookup structure similar
    # to a book's index, letting the database jump straight to matching rows
    # instead of scanning the whole table. This index is on "byte_size"
    # alone, supporting size-based eviction queries. `name:` gives it an
    # explicit, readable name.
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    # A combined (multi-column) index on both "key_hash" and "byte_size"
    # together, speeds up queries that filter/sort by both at once (e.g.
    # eviction logic scanning by size within a hash bucket).
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    # An index on "key_hash" alone, and `unique: true` makes this a UNIQUE
    # INDEX, the database will refuse to insert a second row with a
    # "key_hash" value that already exists. This is what guarantees each
    # cache key maps to at most one stored value (a fresh write for the same
    # key should replace/upsert, never duplicate).
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end
  # This `end` closes the `create_table "solid_cache_entries" do |t|` block
  # that started above, every column and index for this one table has now
  # been fully described.
end
# This final `end` closes the `ActiveRecord::Schema[7.2].define(...) do`
# block opened at the top of the file, there is only one table in this
# database, so this is the last line.
