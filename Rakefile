# WHAT IS THIS FILE?
# Rake is Ruby's built-in task runner (think of it as Ruby's version of a
# Makefile) — it lets you define named commands ("tasks") in Ruby and then
# invoke them from the terminal as `rake <task name>` or, in a Rails app,
# via the `bin/rake` wrapper script. A file literally named `Rakefile`,
# sitting at the root of a project, is the standard entry point Rake looks
# for automatically when you type `rake` from this directory — you never
# pass its filename explicitly.

# Plain-English comment (has no effect on behavior) telling other
# developers where to put NEW custom tasks: any file ending in `.rake`
# placed under lib/tasks is automatically discovered and loaded, without
# needing to be listed here by name.
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

# Blank line — pure visual separation between the comment above and the
# code below; has no effect on execution.

# `require_relative` loads another Ruby file, resolving the given path
# relative to THIS file's own location on disk (as opposed to plain
# `require`, which searches Ruby's load path/installed gems). This loads
# config/application.rb, which defines this app's Rails::Application
# subclass and boots Rails' framework/config — Rake tasks need the full
# Rails app loaded in order to know about Rails- and gem-provided tasks
# (like `db:migrate` or `test`), not just this project's own custom ones.
require_relative "config/application"

# Blank line — pure visual separation.

# `Rails.application` returns the singleton instance of this app's Rails
# application object (the one defined via config/application.rb, loaded
# above). Calling `.load_tasks` on it tells Rails to find and register
# every available Rake task — the framework's built-in tasks (db:*,
# assets:*, etc.), every gem's own tasks, AND this app's custom `.rake`
# files under lib/tasks (per the comment above) — making all of them
# invokable by name from the command line.
Rails.application.load_tasks
