# This is the final step in Rails' boot sequence, after config/boot.rb sets
# up Bundler and config/application.rb defines the app's configuration
# class, this file is what actually turns the lights on and creates the
# running application. Various entry points (the `bin/rails` command, the
# Puma web server, `bin/rails console`, test runners, etc.) all ultimately
# `require` this one file to get a fully working Rails app.

# `require_relative` loads another Ruby file using a path relative to THIS
# file's own location (as opposed to plain `require`, which searches Ruby's
# configured load paths / installed gems). "application" here means
# config/application.rb, in the same config/ directory as this file, no
# ".rb" extension is needed, Ruby adds it automatically. Loading that file
# defines the `Storagefinder::Application` class and runs `config.*` lines
# inside it, but does NOT yet start the app running.
# Load the Rails application.
require_relative "application"

# Blank line separating the "define the app" step above from the
# "actually start it" step below.

# `Rails.application` refers to the single instance of the
# `Storagefinder::Application` class defined in config/application.rb,
# Rails automatically creates that instance when the class is defined.
# `.initialize!` is the method that finally boots the app for real: it runs
# every Rails "initializer" (setup step) in the correct order, loading
# gems' own initializers, setting up autoloading (Zeitwerk, the system
# that automatically finds and loads your Ruby classes/files by name, so
# you never need to `require` your own app/models or app/controllers
# files), connecting middleware, and more. After this line finishes, the
# app is fully ready to handle web requests, run console commands, etc.
# Trying to call `.initialize!` a second time would raise an error, it's
# meant to run exactly once per process.
# Initialize the Rails application.
Rails.application.initialize!
