# This file is a SCHEMA file, not a migration. A "schema" is a snapshot that
# describes the complete, current structure of a database (which tables
# exist, which columns each table has, which indexes speed up lookups) as of
# right now — as opposed to a migration, which describes a single CHANGE to
# apply. Rails can rebuild an empty database instantly by replaying this one
# file, instead of re-running every migration that ever existed one by one.
#
# This particular schema file is for a SEPARATE, secondary database used only
# by the "Solid Queue" gem (Rails' database-backed background job queue —
# the system that runs work like sending emails or crawling websites outside
# of a web request, without needing a separate tool like Redis/Sidekiq).
# Rails 8 apps can have multiple databases wired up (the app's main data, a
# cache store, a queue, a cable store, etc.) and each one gets its own
# schema file like this — that's why this lives in its own file instead of
# inside db/schema.rb.
#
# Like db/schema.rb, this file is auto-generated (by the solid_queue gem's
# own migrations) — you would not hand-edit it in normal use. See the longer
# note in db/schema.rb for why comments added to auto-generated files like
# this one can get overwritten if the underlying migrations are ever re-run.
#
# There are several tables here because a job queue needs to track jobs
# through several different states/concerns: which jobs exist at all
# (solid_queue_jobs), which are ready to run right now (ready_executions),
# which are currently being worked on (claimed_executions), which are
# waiting for a future time (scheduled_executions), which are blocked behind
# a concurrency limit (blocked_executions), which failed (failed_executions),
# which run on a repeating schedule (recurring_tasks/recurring_executions),
# which worker processes exist (processes), which queues are paused
# (pauses), and a low-level locking primitive (semaphores). Below, the first
# occurrence of each new syntax pattern is explained fully; later repeats of
# the same pattern are described more briefly since the mechanics are the
# same.

# `ActiveRecord::Schema[7.1]` says "build this schema using the rules/syntax
# of ActiveRecord as they existed in Rails version 7.1" — pinning a version
# number here means later Rails upgrades won't silently change how this file
# is interpreted. `.define(version: 1) do ... end` starts the block listing
# every table for this database; `version: 1` records that only one
# migration (numbered 1) has ever been run against this specific database.
# The matching `end` at the very bottom of this file closes this block.
ActiveRecord::Schema[7.1].define(version: 1) do
  # `create_table "solid_queue_blocked_executions"` defines a table holding
  # one row per job that's ready to run EXCEPT it's currently blocked by a
  # concurrency limit (e.g. "only run one job with this key at a time").
  # `force: :cascade` tells Rails "if a table with this name already
  # exists, drop and recreate it" — safe here since this file only builds a
  # database from nothing. `do |t|` opens a block where `t` is a
  # table-definition helper; each `t.something` line adds one column.
  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    # `t.bigint "job_id"` adds a column storing a large whole number (a
    # "big integer", for values bigger than a normal 32-bit integer allows)
    # — this identifies which row in "solid_queue_jobs" this blocked
    # execution refers to. `null: false` means this is always required —
    # the database rejects any row missing it.
    t.bigint "job_id", null: false
    # `t.string "queue_name"` adds a text column naming which queue this
    # job belongs to (queues let you group/prioritize different kinds of
    # work). Required.
    t.string "queue_name", null: false
    # `t.integer "priority"` adds a whole-number column controlling run
    # order (lower usually means "runs first," but that's an app-level
    # convention, not something the database enforces). `default: 0` means
    # rows start at priority 0 unless set otherwise. `null: false` means a
    # priority value is always present (never left blank/nil).
    t.integer "priority", default: 0, null: false
    # Text column holding the "concurrency key" — jobs sharing the same key
    # are limited to running one-at-a-time; this is what determines which
    # jobs block each other. Required.
    t.string "concurrency_key", null: false
    # `t.datetime "expires_at"` adds a timestamp column recording when this
    # blocked entry should be considered stale/expired and cleaned up.
    # Required.
    t.datetime "expires_at", null: false
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # `t.index [...]` creates a database INDEX — a lookup structure similar
    # to a book's index, so queries can jump straight to matching rows
    # instead of scanning the whole table. This one covers THREE columns
    # together (`[ "concurrency_key", "priority", "job_id" ]` is a Ruby
    # array/list of column names) — it supports the query "find the next
    # blocked job to release for this concurrency key, in priority order."
    # `name:` gives the index an explicit, readable name.
    t.index [ "concurrency_key", "priority", "job_id" ], name: "index_solid_queue_blocked_executions_for_release"
    # A two-column index supporting maintenance queries like "find blocked
    # entries that have expired for this concurrency key."
    t.index [ "expires_at", "concurrency_key" ], name: "index_solid_queue_blocked_executions_for_maintenance"
    # A single-column index on "job_id", and `unique: true` makes it a
    # UNIQUE INDEX — the database refuses a second row with the same
    # job_id, guaranteeing a given job can only be in the "blocked" state
    # once at a time.
    t.index [ "job_id" ], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end
  # Closes the `create_table "solid_queue_blocked_executions" do |t|` block.

  # Table holding one row per job that a worker process has currently
  # "claimed" (picked up to actually execute right now).
  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    # Big-integer column identifying which job (in solid_queue_jobs) this
    # claim is for. Required.
    t.bigint "job_id", null: false
    # Big-integer column identifying which worker process claimed this job
    # — links to solid_queue_processes. No `null: false`, so this column is
    # OPTIONAL (can be nil, e.g. momentarily between states).
    t.bigint "process_id"
    # Timestamp column recording when the claim was made. Required.
    t.datetime "created_at", null: false
    # Unique index on "job_id" — a job can only be claimed once at a time.
    t.index [ "job_id" ], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    # Two-column (non-unique) index supporting "find all jobs claimed by
    # this process" queries, ordered/filtered by job_id too.
    t.index [ "process_id", "job_id" ], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end
  # Closes the `create_table "solid_queue_claimed_executions" do |t|` block.

  # Table holding one row per job execution that failed, so failures can be
  # inspected/retried instead of silently disappearing.
  create_table "solid_queue_failed_executions", force: :cascade do |t|
    # Big-integer column identifying which job failed. Required.
    t.bigint "job_id", null: false
    # `t.text "error"` adds a column for longer free-form text than
    # `t.string` typically allows — holds the error message/backtrace from
    # the failure. Optional (no null: false) — though in practice a failed
    # row would normally have one.
    t.text "error"
    # Timestamp column recording when the failure was recorded. Required.
    t.datetime "created_at", null: false
    # Unique index on "job_id" — a given job has at most one failure record
    # at a time.
    t.index [ "job_id" ], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end
  # Closes the `create_table "solid_queue_failed_executions" do |t|` block.

  # The main jobs table — one row per background job that has ever been
  # enqueued, regardless of what state it's currently in.
  create_table "solid_queue_jobs", force: :cascade do |t|
    # Text column naming which queue this job was enqueued on. Required.
    t.string "queue_name", null: false
    # Text column holding the Ruby class name of the job to run (e.g.
    # "CrawlFacilitiesJob") — this is how Solid Queue knows what code to
    # actually execute for this row. Required.
    t.string "class_name", null: false
    # Longer free-form text column holding the job's arguments, serialized
    # (e.g. as JSON) into one string. Optional.
    t.text "arguments"
    # Whole-number column for run-order priority, defaulting to 0.
    # Required (never left blank).
    t.integer "priority", default: 0, null: false
    # Text column holding Rails' own internal ActiveJob id for this job (a
    # separate identifier from this row's own database id) — lets
    # ActiveJob correlate its job objects with Solid Queue's rows. Optional.
    t.string "active_job_id"
    # Timestamp column recording when this job is scheduled to run (for
    # delayed jobs). Optional — nil for jobs meant to run immediately.
    t.datetime "scheduled_at"
    # Timestamp column recording when this job finished running (whether it
    # succeeded or failed). Optional — nil while still pending/running.
    t.datetime "finished_at"
    # Text column holding a concurrency key for this job, if it has one
    # (used to decide whether it should be blocked behind another job with
    # the same key). Optional.
    t.string "concurrency_key"
    # Timestamp column recording when the job row was created. Required.
    t.datetime "created_at", null: false
    # Timestamp column recording when the job row was last updated.
    # Required.
    t.datetime "updated_at", null: false
    # Index speeding up lookups by ActiveJob id (correlating back to the
    # ActiveJob object that enqueued this row).
    t.index [ "active_job_id" ], name: "index_solid_queue_jobs_on_active_job_id"
    # Index speeding up lookups/filters by job class name.
    t.index [ "class_name" ], name: "index_solid_queue_jobs_on_class_name"
    # Index speeding up lookups/filters by when a job finished (e.g.
    # "show recently finished jobs").
    t.index [ "finished_at" ], name: "index_solid_queue_jobs_on_finished_at"
    # Two-column index supporting "filter jobs on this queue by whether
    # they're finished" queries.
    t.index [ "queue_name", "finished_at" ], name: "index_solid_queue_jobs_for_filtering"
    # Two-column index supporting queries that look for jobs approaching
    # (or past) their scheduled time but not yet finished — used for
    # alerting on stuck/overdue jobs.
    t.index [ "scheduled_at", "finished_at" ], name: "index_solid_queue_jobs_for_alerting"
  end
  # Closes the `create_table "solid_queue_jobs" do |t|` block.

  # Table holding one row per queue that has been manually paused (a paused
  # queue's jobs are held back from running until unpaused).
  create_table "solid_queue_pauses", force: :cascade do |t|
    # Text column naming the paused queue. Required.
    t.string "queue_name", null: false
    # Timestamp column recording when the pause was created. Required.
    t.datetime "created_at", null: false
    # Unique index on "queue_name" — a given queue can only have one pause
    # record (it's either paused or it isn't, not paused multiple times).
    t.index [ "queue_name" ], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end
  # Closes the `create_table "solid_queue_pauses" do |t|` block.

  # Table holding one row per worker process (the actual OS processes
  # executing jobs) that Solid Queue is tracking.
  create_table "solid_queue_processes", force: :cascade do |t|
    # Text column describing what kind of process this is (e.g.
    # "Worker", "Dispatcher", "Scheduler" — different roles within Solid
    # Queue's architecture). Required.
    t.string "kind", null: false
    # Timestamp column recording the last time this process "checked in" to
    # prove it's still alive — used to detect crashed/dead processes.
    # Required.
    t.datetime "last_heartbeat_at", null: false
    # Big-integer column linking to a parent/supervising process, if this
    # process was started by one. Optional (top-level processes have none).
    t.bigint "supervisor_id"
    # `t.integer "pid"` adds a whole-number column for the operating
    # system's process ID number. Required.
    t.integer "pid", null: false
    # Text column recording which machine/host this process is running on.
    # Optional.
    t.string "hostname"
    # Longer free-form text column for miscellaneous extra process
    # information, likely serialized (e.g. as JSON) into one string.
    # Optional.
    t.text "metadata"
    # Timestamp column recording when this process record was created.
    # Required.
    t.datetime "created_at", null: false
    # Text column for the process's name. Required.
    t.string "name", null: false
    # Index speeding up lookups/filters by last heartbeat time (finding
    # processes that have gone quiet/died).
    t.index [ "last_heartbeat_at" ], name: "index_solid_queue_processes_on_last_heartbeat_at"
    # Two-column unique index — a process name must be unique WITHIN a
    # given supervisor (no two sibling processes share a name under the
    # same supervisor).
    t.index [ "name", "supervisor_id" ], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    # Index speeding up lookups of all processes under a given supervisor.
    t.index [ "supervisor_id" ], name: "index_solid_queue_processes_on_supervisor_id"
  end
  # Closes the `create_table "solid_queue_processes" do |t|` block.

  # Table holding one row per job that is ready to run right now (not
  # blocked, not scheduled for later) — workers poll this table to find
  # work.
  create_table "solid_queue_ready_executions", force: :cascade do |t|
    # Big-integer column identifying which job this is. Required.
    t.bigint "job_id", null: false
    # Text column naming which queue this ready job belongs to. Required.
    t.string "queue_name", null: false
    # Whole-number priority column, defaulting to 0. Required.
    t.integer "priority", default: 0, null: false
    # Timestamp column recording when this ready row was created. Required.
    t.datetime "created_at", null: false
    # Unique index on "job_id" — a job appears in the "ready" state at most
    # once at a time.
    t.index [ "job_id" ], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    # Two-column index supporting "poll for the next job to run across all
    # queues, in priority order" — the naming ("poll_all") reflects that
    # this is used by workers polling without restricting to one queue.
    t.index [ "priority", "job_id" ], name: "index_solid_queue_poll_all"
    # Three-column index supporting the same kind of polling query, but
    # restricted to one specific queue at a time ("poll_by_queue").
    t.index [ "queue_name", "priority", "job_id" ], name: "index_solid_queue_poll_by_queue"
  end
  # Closes the `create_table "solid_queue_ready_executions" do |t|` block.

  # Table holding one row per SCHEDULED occurrence of a recurring task
  # (e.g. "run the daily crawl job for 2026-07-22") — links a recurring
  # task definition to the actual job it produced.
  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    # Big-integer column identifying the job this recurring execution
    # produced. Required.
    t.bigint "job_id", null: false
    # Text column identifying which recurring task definition (by key) this
    # execution belongs to. Required.
    t.string "task_key", null: false
    # Timestamp column recording which scheduled run-time this execution
    # corresponds to. Required.
    t.datetime "run_at", null: false
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Unique index on "job_id" — each job corresponds to exactly one
    # recurring execution record.
    t.index [ "job_id" ], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    # Two-column UNIQUE index on (task_key, run_at) — guarantees the same
    # recurring task can't be scheduled to run twice for the same run_at
    # timestamp (prevents duplicate runs of a cron-like schedule).
    t.index [ "task_key", "run_at" ], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end
  # Closes the `create_table "solid_queue_recurring_executions" do |t|` block.

  # Table holding one row per DEFINED recurring task (the schedule/rule
  # itself, e.g. "run this job every day at 6am") — distinct from the table
  # above, which tracks individual scheduled occurrences of these rules.
  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    # Text column with this task's unique key/identifier. Required.
    t.string "key", null: false
    # Text column holding the schedule, typically in cron format (e.g.
    # "0 6 * * *" for daily at 6am). Required.
    t.string "schedule", null: false
    # Text column that can hold a shell/command string to run, if this task
    # isn't defined as a Ruby job class. `limit: 2048` caps it at 2048
    # characters. Optional.
    t.string "command", limit: 2048
    # Text column holding the Ruby job class name to run for this task, if
    # defined that way instead of via a raw command. Optional.
    t.string "class_name"
    # Text column naming which queue jobs from this task should run on.
    # Optional.
    t.string "queue_name"
    # Whole-number priority column for jobs produced by this task.
    # `default: 0`, and no `null: false` here (unlike similar priority
    # columns above) — so this one CAN be left nil, unlike the others.
    t.integer "priority", default: 0
    # Boolean column recording whether this task is defined statically (in
    # application configuration) as opposed to created dynamically at
    # runtime. `default: true`, and `null: false` means it's always
    # present (true or false, never nil).
    t.boolean "static", default: true, null: false
    # Longer free-form text column for a human-readable description of what
    # this task does. Optional.
    t.text "description"
    # Timestamp column recording when this task definition was created.
    # Required.
    t.datetime "created_at", null: false
    # Timestamp column recording when this task definition was last
    # updated. Required.
    t.datetime "updated_at", null: false
    # Unique index on "key" — each recurring task's key must be unique, so
    # there's exactly one definition per key.
    t.index [ "key" ], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    # Index speeding up filtering tasks by whether they're statically
    # defined.
    t.index [ "static" ], name: "index_solid_queue_recurring_tasks_on_static"
  end
  # Closes the `create_table "solid_queue_recurring_tasks" do |t|` block.

  # Table holding one row per job that's scheduled to run at a future time
  # (as opposed to "ready" jobs, which should run immediately).
  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    # Big-integer column identifying which job this is. Required.
    t.bigint "job_id", null: false
    # Text column naming which queue this scheduled job belongs to.
    # Required.
    t.string "queue_name", null: false
    # Whole-number priority column, defaulting to 0. Required.
    t.integer "priority", default: 0, null: false
    # Timestamp column recording the future time this job should run.
    # Required.
    t.datetime "scheduled_at", null: false
    # Timestamp column recording when this row was created. Required.
    t.datetime "created_at", null: false
    # Unique index on "job_id" — a job is scheduled at most once at a time.
    t.index [ "job_id" ], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    # Three-column index supporting the "dispatch" query — finding jobs
    # whose scheduled time has arrived, across all queues, in priority
    # order, so they can be moved into the "ready" table.
    t.index [ "scheduled_at", "priority", "job_id" ], name: "index_solid_queue_dispatch_all"
  end
  # Closes the `create_table "solid_queue_scheduled_executions" do |t|` block.

  # Table implementing SEMAPHORES — a low-level concurrency-control
  # primitive (like a counter with a limit) used internally to enforce
  # "only N jobs with this key may run at once" rules.
  create_table "solid_queue_semaphores", force: :cascade do |t|
    # Text column holding the semaphore's key (matches a job's concurrency
    # key). Required.
    t.string "key", null: false
    # Whole-number column holding the semaphore's current count/value.
    # `default: 1` and `null: false` mean it starts at 1 (available) and is
    # always present.
    t.integer "value", default: 1, null: false
    # Timestamp column recording when this semaphore should be considered
    # stale/expired, as a safety net against permanently stuck locks.
    # Required.
    t.datetime "expires_at", null: false
    # Timestamp column recording when this semaphore row was created.
    # Required.
    t.datetime "created_at", null: false
    # Timestamp column recording when this semaphore row was last updated.
    # Required.
    t.datetime "updated_at", null: false
    # Index speeding up cleanup queries that look for expired semaphores.
    t.index [ "expires_at" ], name: "index_solid_queue_semaphores_on_expires_at"
    # Two-column (non-unique) index supporting lookups by key and current
    # value together.
    t.index [ "key", "value" ], name: "index_solid_queue_semaphores_on_key_and_value"
    # Unique index on "key" — each concurrency key has exactly one
    # semaphore row tracking it.
    t.index [ "key" ], name: "index_solid_queue_semaphores_on_key", unique: true
  end
  # Closes the `create_table "solid_queue_semaphores" do |t|` block.

  # `add_foreign_key` adds a FOREIGN KEY constraint to an existing table — a
  # database-level rule that a column's value must match an existing row's
  # id in another table (here, that "job_id" must point at a real row in
  # "solid_queue_jobs"). This protects data integrity even if application
  # code has a bug that tries to insert an orphaned row. `column:
  # "job_id"` tells Rails which column on "solid_queue_blocked_executions"
  # holds the reference (needed because the table name and the referenced
  # table name — "solid_queue_jobs" — don't match by Rails' usual naming
  # convention). `on_delete: :cascade` tells the DATABASE to automatically
  # delete any row here whenever the "solid_queue_jobs" row it points to is
  # deleted — so finishing/removing a job automatically cleans up its
  # related blocked-execution row too, without the app having to do it
  # manually.
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  # Same pattern: claimed_executions rows are auto-deleted when their job
  # is deleted.
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  # Same pattern: failed_executions rows are auto-deleted when their job is
  # deleted.
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  # Same pattern: ready_executions rows are auto-deleted when their job is
  # deleted.
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  # Same pattern: recurring_executions rows are auto-deleted when their job
  # is deleted.
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  # Same pattern: scheduled_executions rows are auto-deleted when their job
  # is deleted. Note there is no equivalent add_foreign_key line for
  # "solid_queue_processes.supervisor_id" or
  # "solid_queue_claimed_executions.process_id" — those references are left
  # unenforced at the database level (see flagged observations at the end
  # of this review).
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
# This final `end` closes the `ActiveRecord::Schema[7.1].define(...) do`
# block opened at the top of the file.
