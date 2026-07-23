# WHAT IS THIS FILE?
# Rack is the low-level standard interface that (almost) every Ruby web
# server and web framework agrees to speak — it defines a simple contract
# ("given an HTTP request, return a status code, headers, and a body") that
# lets any Rack-compatible server (like Puma, used by this app — see the
# Gemfile) run any Rack-compatible application (like Rails itself) without
# either one needing to know the other's internals. A file named
# `config.ru` ("ru" = "rack up") is the standard place Rack-aware servers
# look for instructions on what application to actually run — when Puma
# starts, it reads this file to find out "run Rails.application" rather
# than needing that wired in some other way. This is Ruby code, evaluated
# top to bottom, but written specifically in Rack's small DSL (domain-
# specific language) of just a couple of special methods like `run` below.

# Comment (pre-existing) summarizing this file's purpose in plain English —
# has no effect on behavior.
# This file is used by Rack-based servers to start the application.

# Blank line — pure visual separation.

# `require_relative` loads another Ruby file, resolved relative to this
# file's own location on disk. This loads config/environment.rb, which in
# turn boots the entire Rails framework — loading all of this app's code,
# initializers, and configuration — so that by the time the next line runs,
# `Rails.application` is fully available and ready to handle requests.
require_relative "config/environment"

# Blank line — pure visual separation.

# `run` is Rack's DSL method (defined by the Rack gem, made available
# implicitly in a config.ru file) that declares WHICH object should handle
# every incoming HTTP request. `Rails.application` is the singleton
# instance of this app's Rails::Application subclass — passing it to `run`
# tells the Rack-compatible web server (Puma) to hand every request to
# Rails' router, which then dispatches to the matching controller action.
run Rails.application
# `Rails.application.load_server` runs additional Rails setup that's
# specifically needed only when Rails is being booted AS a running server
# process (as opposed to, say, a one-off Rake task or console session) —
# for example, wiring up server-specific behavior. It's called after `run`
# above sets the request handler, completing the server-mode boot sequence.
Rails.application.load_server
