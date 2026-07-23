# Puma is the web server that actually listens on a network port, accepts
# incoming HTTP requests from browsers, and hands them to your Rails app to
# generate a response. This file configures Puma. It is NOT a normal Ruby
# class/module file — Puma reads it and runs it top to bottom as a script,
# using special method calls (`threads`, `port`, `plugin`, `pidfile` below)
# that only exist because Puma defines them; they're not standard Ruby.
#
# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
# (All the paragraphs above are Rails' original generated explanation of
# Puma's process/thread model — kept as-is since it's already thorough.
# Below, each remaining line of actual configuration is commented too.)

# `ENV` is Ruby's built-in Hash-like object holding environment variables
# (settings passed in from outside the app, e.g. by your shell or a deploy
# tool). `.fetch("RAILS_MAX_THREADS", 3)` looks up the variable named
# "RAILS_MAX_THREADS"; if it isn't set, it falls back to the default value
# `3` given as the second argument (note: env vars are always strings when
# set, so if RAILS_MAX_THREADS=5 were set, threads_count would be the
# string "5", not the integer 5 — Puma's `threads` method below handles
# that conversion). The result is stored in a local variable named
# `threads_count` for reuse on the next line.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
# `threads` is one of Puma's DSL methods (not plain Ruby) — it takes a
# minimum and maximum thread-pool size per worker process. Passing the same
# value (`threads_count`) for both means "always run exactly this many
# threads," rather than letting Puma scale the pool up and down within a
# range.
threads threads_count, threads_count

# Blank line separating the threads setting from the port setting below.

# `port` is another Puma DSL method: it sets which network port the server
# listens on for incoming HTTP connections. `ENV.fetch("PORT", 3000)` reads
# the PORT environment variable, defaulting to 3000 if it isn't set — this
# lets a deploy environment (or config/environments/development.rb, which
# sets `default_url_options` to port 5555 for mailer links — note this is a
# different, unrelated setting) override which port to actually bind to.
# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Blank line separating the port setting from the plugin declarations below.

# `plugin` is a Puma DSL method that turns on an optional Puma feature by
# name (as a Ruby symbol — `:tmp_restart` — a lightweight, immutable label
# used instead of a string for fixed internal names like this). The
# `tmp_restart` plugin makes Puma watch for the file tmp/restart.txt being
# touched (updated) and gracefully restarts itself when that happens — this
# is what `bin/rails restart` uses to signal a running server without you
# having to manually stop/start it.
# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# This line turns on the `solid_queue` Puma plugin, which would run Solid
# Queue's background-job supervisor as a thread inside the same Puma
# process (useful for simple single-server deployments so you don't need a
# separate worker process). `if ENV["SOLID_QUEUE_IN_PUMA"]` means this only
# happens when that environment variable is set to any truthy value (Ruby
# treats any non-nil, non-false value — including the string "false" — as
# "true" in an `if`, so this is really "is the env var present at all").
# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Blank line separating the plugin declarations from the pidfile setting.

# `pidfile` is a Puma DSL method that tells Puma to write its own process ID
# to a file at the given path, so external tools can find/signal the
# running server process. `ENV["PIDFILE"] if ENV["PIDFILE"]` is a common
# Ruby idiom: it only calls `pidfile(...)` at all when the PIDFILE
# environment variable is actually set (non-nil) — if it's unset, this
# whole line does nothing, and Puma falls back to its own default
# (tmp/pids/server.pid in development, as the comment below notes).
# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
