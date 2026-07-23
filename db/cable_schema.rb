# This file is a SCHEMA file, not a migration. A "schema" is a snapshot that
# describes the complete, current structure of a database (which tables
# exist, which columns each table has, which indexes speed up lookups) as of
# right now — as opposed to a migration, which describes a single CHANGE to
# apply. Rails can rebuild an empty database instantly by replaying this one
# file, instead of re-running every migration that ever existed one by one.
#
# This particular schema file is for a SEPARATE, secondary database used only
# by the "Solid Cable" gem (Rails' database-backed alternative to Redis for
# ActionCable/WebSocket pub-sub messaging). Rails 8 apps can have multiple
# databases wired up (the app's main data, a cache store, a queue, a cable
# store, etc.) and each one gets its own schema file like this — that's why
# this lives in its own file instead of inside db/schema.rb.
#
# Like db/schema.rb, this file is auto-generated (by the solid_cable gem's
# own migrations) — you would not hand-edit it in normal use. See the longer
# note in db/schema.rb for why comments added to auto-generated files like
# this one can get overwritten if the underlying migrations are ever re-run.

# `ActiveRecord::Schema[7.1]` says "build this schema using the rules/syntax
# of ActiveRecord as they existed in Rails version 7.1" — pinning a version
# number here means later Rails upgrades won't silently change how this file
# is interpreted. `.define(version: 1) do ... end` starts the block that
# lists every table for this database; `version: 1` records that only one
# migration (numbered 1) has ever been run against this specific database,
# so Rails knows not to re-run it. The matching `end` at the very bottom of
# this file closes this `.define do` block.
ActiveRecord::Schema[7.1].define(version: 1) do
  # `create_table "solid_cable_messages"` defines a database table (think:
  # a spreadsheet with named columns) called "solid_cable_messages" — this is
  # where every WebSocket broadcast message gets temporarily stored so other
  # server processes can pick it up. `force: :cascade` tells Rails "if a
  # table with this name already exists, drop it first and recreate it from
  # scratch" — safe here because this file is only used to build a database
  # from nothing. `do |t|` opens a block where `t` is a table-definition
  # helper object — each `t.something` line below adds one column to the
  # table. The matching `end` two lines from the bottom of this block closes
  # this `create_table` call.
  create_table "solid_cable_messages", force: :cascade do |t|
    # `t.binary "channel"` adds a column named "channel" that stores raw
    # binary data (not readable text) — this holds the identifier for which
    # WebSocket channel/stream a message belongs to. `limit: 1024` caps it at
    # 1024 bytes. `null: false` means this column can never be left empty
    # (every row MUST have a value here) — the database itself enforces this,
    # rejecting any insert that omits it.
    t.binary "channel", limit: 1024, null: false
    # `t.binary "payload"` stores the actual message contents being
    # broadcast, also as raw binary data. `limit: 536870912` allows up to
    # 512 megabytes (536,870,912 bytes) — a generous ceiling so large
    # broadcasts aren't rejected. `null: false` again means this is required.
    t.binary "payload", limit: 536870912, null: false
    # `t.datetime "created_at"` adds a timestamp column recording exactly
    # when this message row was inserted — used to find/prune old messages.
    # `null: false` means every row must have a creation time recorded.
    t.datetime "created_at", null: false
    # `t.integer "channel_hash"` stores a numeric hash (a fixed-size
    # fingerprint) computed from the channel name, so the database can look
    # up "all messages for this channel" by comparing fast integers instead
    # of comparing the full binary "channel" value each time. `limit: 8`
    # means this integer uses 8 bytes of storage (a "bigint", allowing very
    # large numbers). `null: false` means it's always required.
    t.integer "channel_hash", limit: 8, null: false
    # `t.index [...]` creates a database INDEX — a lookup structure similar
    # to a book's index, letting the database jump straight to matching rows
    # instead of scanning the whole table. This index is built on the
    # "channel" column alone. `name:` gives the index an explicit, readable
    # name (otherwise Rails would auto-generate one) so it's easy to find in
    # database tooling later.
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    # A second index, this time on "channel_hash" — used for the fast
    # hash-based channel lookups described above.
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    # A third index, on "created_at" — speeds up queries that clean up or
    # sort messages by how old they are.
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end
  # This `end` closes the `create_table "solid_cable_messages" do |t|` block
  # that started above — every column and index for this one table has now
  # been fully described.
end
# This final `end` closes the `ActiveRecord::Schema[7.1].define(...) do`
# block opened at the top of the file — there is only one table in this
# database, so this is the last line.
