# This file is the very first Ruby file Rails loads when your app starts,
# before Rails itself is even loaded. Its job is just to get "Bundler" (the
# tool that manages your gems, i.e. installed Ruby libraries) ready to go.

# `ENV` is a special Ruby Hash-like object that holds environment variables,
# key/value settings that live outside your code, in the operating system's
# process environment (things like PATH, or here, which Gemfile to use).
# `ENV["BUNDLE_GEMFILE"]` reads the current value of that variable, if any.
# `||=` means "set this only if it isn't already set", it's shorthand for
# `ENV["BUNDLE_GEMFILE"] = ENV["BUNDLE_GEMFILE"] || File.expand_path(...)`.
# This lets something outside the app (like a deploy script) override which
# Gemfile to use, while still having a sensible default here.
# `File.expand_path("../Gemfile", __dir__)` builds an absolute file path to
# the Gemfile. `__dir__` is a Ruby keyword meaning "the directory this file
# (boot.rb) lives in", i.e. config/. `"../Gemfile"` means "go up one
# directory from config/, then look for Gemfile", which lands at the
# project root's Gemfile, since that's where Rails apps keep it.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# `require` loads a Ruby library by name so its code becomes available to
# use. "bundler/setup" is part of the Bundler gem itself, requiring it
# configures Ruby's `$LOAD_PATH` (the list of folders Ruby searches when you
# `require` something) so that only the exact gem versions locked in your
# Gemfile.lock can be loaded, this is what keeps "works on my machine"
# gem-version mismatches from happening. The trailing `#` starts a Ruby
# comment that runs to the end of the line, this one restates what the line
# does in plain English, which is the original codebase's own comment style.
require "bundler/setup" # Set up gems listed in the Gemfile.

# Bootsnap is a separate gem (from Shopify) that caches the expensive results
# of parsing/compiling Ruby files and other lookups to disk, so subsequent
# app boots are much faster. Requiring "bootsnap/setup" turns this caching on
# for the rest of the boot process (and hooks itself into Ruby's require
# mechanism so it also speeds up gem loading elsewhere in the app).
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
