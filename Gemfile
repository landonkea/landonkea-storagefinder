# WHAT IS THIS FILE?
# A "gem" is Ruby's word for a packaged, reusable library that someone
# published for others to reuse (similar to an npm package in JavaScript,
# or a pip package in Python). This file, `Gemfile`, is read by Bundler
# (a gem-management tool bundled with Ruby) to know exactly which gems —
# and which versions of them — this application depends on. Running
# `bundle install` reads this file, resolves compatible versions for every
# gem listed (recording the exact result in Gemfile.lock, a sibling file
# NOT covered by this comment pass), downloads them, and makes them
# available to `require` throughout the app. Rails itself is just a gem
# (line below), and everything this app can do beyond plain Ruby comes from
# some gem listed somewhere in this file.

# `source "https://rubygems.org"` tells Bundler WHERE to download gems
# from — rubygems.org is the main public gem registry (the default/
# standard place almost all Ruby projects pull from), similar to how npm
# pulls from npmjs.com by default.
source "https://rubygems.org"

# Blank line — pure visual separation; has no effect on Bundler.

# `ruby ">= 3.2"` declares the minimum Ruby language VERSION this app
# requires — Bundler checks the Ruby interpreter actually running against
# this constraint and refuses to proceed if it's too old. `">= 3.2"` is a
# version-requirement string understood by Bundler/RubyGems: "any version
# 3.2.0 or newer." (Separately, .ruby-version pins the EXACT version used
# for this project locally/in CI — that file is intentionally excluded
# from this comment pass per the style guide.)
ruby ">= 3.2"

# Blank line — pure visual separation.

# `gem "rails", "~> 8.1"` pulls in the Rails web framework itself — the
# foundation this entire application is built on (routing, controllers,
# views, ActiveRecord database models, etc.). The string `"~> 8.1"` is
# RubyGems' "pessimistic" (a.k.a. "twiddle-wakka") version constraint
# operator: it means "allow any 8.x version that is >= 8.1, but never
# jump to 9.0" — i.e. accept patch/minor updates automatically, but never
# an update that could introduce breaking major-version changes.
gem "rails", "~> 8.1"
# `gem "propshaft"` adds Rails' modern asset pipeline gem — it's what takes
# files under app/assets (CSS, images, etc.) and prepares them for the
# browser (fingerprinted filenames for cache-busting, etc.), replacing the
# older Sprockets pipeline used by pre-Rails-8 apps.
gem "propshaft"
# `gem "tailwindcss-rails"` integrates the Tailwind CSS utility framework
# (see app/assets/tailwind/application.css) into Rails' asset pipeline. It
# provides the `bin/rails tailwindcss:build`/`tailwindcss:watch` Rake tasks
# that Procfile.dev's "css:" process runs, by downloading and wrapping a
# platform-specific standalone `tailwindcss` command-line tool (no Node.js/
# npm required) that reads app/assets/tailwind/application.css and writes
# the compiled output to app/assets/builds/tailwind.css, which Propshaft
# then serves to the browser.
gem "tailwindcss-rails"
# `gem "sqlite3", ">= 2.1"` adds the Ruby bindings for SQLite, the
# file-based (no separate server process needed) database this app uses to
# store its data — see config/database.yml for how Rails is told to use it.
# `">= 2.1"` allows any version 2.1 or newer, with no upper bound.
gem "sqlite3", ">= 2.1"
# `gem "puma", ">= 5.0"` adds Puma, the actual HTTP server process that
# accepts browser requests and hands them to Rails (see config.ru for where
# it's wired in as the Rack app runner). `">= 5.0"` again means "5.0 or
# any newer version."
gem "puma", ">= 5.0"
# `gem "importmap-rails"` lets this app serve JavaScript directly to the
# browser using native browser "import maps," without needing a Node.js/
# npm/webpack build step to bundle JS files together.
gem "importmap-rails"
# `gem "turbo-rails"` adds Turbo (part of the Hotwire family), which speeds
# up page navigation and lets parts of a page update without a full reload,
# largely by intercepting normal link clicks/form submits and swapping in
# server-rendered HTML fragments instead.
gem "turbo-rails"
# `gem "stimulus-rails"` adds Stimulus (also part of Hotwire), a small
# JavaScript framework for attaching behavior to existing server-rendered
# HTML (e.g. "when this button is clicked, run this bit of JS"), as opposed
# to frameworks that generate the HTML client-side themselves.
gem "stimulus-rails"
# `gem "jbuilder"` adds a DSL (mini-language) for building JSON responses
# using ordinary `.jbuilder` view template files — useful for any API-style
# endpoints this app exposes, similar to how `.erb` templates build HTML.
gem "jbuilder"
# `gem "playwright-ruby-client"` adds Ruby bindings for Playwright, a
# browser-automation tool (drives a real Chrome/Firefox/WebKit browser
# programmatically) — likely used here for scraping other storage-facility
# sites and/or for browser-based system tests.
gem "playwright-ruby-client"
# `gem "geocoder"` adds address/location lookup helpers — turning a street
# address into latitude/longitude coordinates (or vice versa) and
# calculating distances between locations, useful for a storage-unit
# finder app that likely searches "near me."
gem "geocoder"
# `gem "chartkick"` adds simple chart-drawing view helpers (line charts,
# bar charts, etc.) that generate the JavaScript needed to render a chart
# from Ruby data, without hand-writing charting JS yourself.
gem "chartkick"
# `gem "groupdate"` adds ActiveRecord query helpers for grouping database
# records by time period (e.g. "count of X per day/week/month") — commonly
# paired with chartkick above to build time-series charts.
gem "groupdate"
# `gem "caxlsx"` adds the ability to generate real Microsoft Excel (.xlsx)
# spreadsheet files from Ruby code — useful for "export to Excel" features.
gem "caxlsx"
# `gem "caxlsx_rails"` adds Rails integration on top of caxlsx above,
# letting controllers respond to a request with `format.xlsx` the same way
# they'd respond with `format.html` or `format.json`.
gem "caxlsx_rails"
# `gem "csv"` adds Ruby's CSV (comma-separated values) library. This used
# to ship as part of Ruby's "default gems" automatically; newer Ruby
# versions are trimming their default/bundled gem list, so it's listed
# here explicitly to guarantee it's available regardless of Ruby version.
gem "csv"
# `gem "ostruct"` adds Ruby's OpenStruct class (a quick way to build an
# object with arbitrary attributes on the fly, without defining a class for
# it first). The trailing `# used by ...` text is an inline comment (a
# comment placed after code on the same line, following `#`) — it was
# already here and explains specifically WHERE this gem is used
# (SettingsController#test_email) and WHY it must be listed explicitly:
# ostruct, like csv above, is being removed from Ruby's bundled default
# gems as of Ruby 4.0, so apps that use it must depend on it directly.
gem "ostruct" # used by SettingsController#test_email; moving out of Ruby's default gems in 4.0
# `gem "dnssd", require: false` adds DNS Service Discovery bindings
# (finding devices/services advertised on a local network via
# Bonjour/Zeroconf-style protocols). The `require: false` option tells
# Bundler "install this gem, but don't automatically `require` it when the
# app boots" — some other piece of code must `require "dnssd"` explicitly,
# exactly when it's actually needed, which avoids paying the cost of
# loading it on every boot if it's rarely used.
gem "dnssd", require: false
# `gem "mail"` adds Ruby's general-purpose email-composing/parsing library
# — the same library ActionMailer (Rails' built-in mailer framework) is
# itself built on top of; listed directly here likely because some code
# uses it straight, not just through ActionMailer.
gem "mail"
# `gem "faraday"` adds an HTTP client library used for making outbound web
# requests (e.g. calling external APIs) from Ruby code, with a pluggable
# "adapter" design so the underlying HTTP engine can be swapped out.
gem "faraday"
# `gem "faraday-multipart"` adds an extension (middleware) for Faraday
# above that adds support for "multipart" request bodies — the format
# needed to, for example, upload a file as part of an HTTP request.
gem "faraday-multipart"
# `gem "amazing_print"` adds prettier, syntax-highlighted, more readable
# console/log output when inspecting Ruby objects (e.g. in `bin/rails
# console`) compared to Ruby's plain built-in `.inspect` formatting.
gem "amazing_print"
# `gem "bootsnap", require: false` adds Bootsnap, which caches expensive
# parts of Ruby's boot process (like parsing large files) to disk so
# subsequent app boots are noticeably faster. `require: false` here because
# Bootsnap is loaded explicitly, very early, from boot.rb — not via the
# normal Bundler.require path — so it must not also auto-require at the
# normal point or it'd effectively load twice / too late to help.
gem "bootsnap", require: false

# Blank line — pure visual separation before the next commented gem entry.

# Comment (pre-existing) explaining both WHAT this gem is for and WHY it's
# required at all: Kamal is a deployment tool (see the URL) for shipping a
# Rails app as a Docker container to any server; this app's own bin/kamal
# script and config/deploy.yml configuration file both assume the `kamal`
# gem is installed, so without this line, running `bin/kamal` would
# immediately fail with a "could not find gem kamal" error rather than
# actually attempting a deploy.
# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# bin/kamal and config/deploy.yml already assume this — without the gem,
# bin/kamal fails immediately with "could not find gem kamal".
# `require: false` — same meaning as above: install the gem, but don't
# auto-load it at boot, since it's only needed when the `bin/kamal` command
# itself is actually run, not during normal app startup/requests.
gem "kamal", require: false

# Blank line — pure visual separation before the first `group` block.

# `group :development, :test do ... end` is Bundler's way of scoping a set
# of gems to only certain environments. Passing two symbols (`:development`
# and `:test`, Ruby's lightweight "named constant/label" values — written
# with a leading colon, cheaper than a String and typically used as an
# identifier rather than displayable text) means every gem listed inside
# this block is installed ONLY when Bundler is asked for the development or
# test group — e.g. NOT in the production Docker image (see the Dockerfile,
# which sets `BUNDLE_WITHOUT="development"`). `do...end` is Ruby's block
# syntax: `do` opens a block of code passed to the `group` method, and the
# matching `end` (below) closes it.
group :development, :test do
  # `gem "debug"` adds Ruby's standard interactive debugger — lets you drop
  # a `debugger` breakpoint into code and step through execution live.
  gem "debug"

  # Blank line — pure visual separation inside the group block.

  # Comment (pre-existing) explaining WHY these three specific gems are
  # listed together: the wrapper scripts bin/bundler-audit, bin/brakeman,
  # and bin/rubocop already exist in this repo and are invoked by
  # .github/workflows/ci.yml's scan_ruby and lint jobs — meaning CI expects
  # these tools to be available. NOTE: as currently written, this comment's
  # claim that the gems "were never added" appears to be stale/inaccurate,
  # since the three `gem` lines immediately below DO add them — see the
  # flagged-issues note in the final report for details; this comment is
  # being preserved as-is (not corrected), per the "flag, don't fix" rule.
  # bin/bundler-audit, bin/brakeman, and bin/rubocop already exist and are
  # wired into .github/workflows/ci.yml's scan_ruby/lint jobs, but none of
  # these three gems were ever added — every CI run fails immediately on them.
  # `gem "bundler-audit", require: false` adds a tool that checks every gem
  # version locked in Gemfile.lock against a public database of known
  # security vulnerabilities. `require: false` — not needed at app boot,
  # only when the `bin/bundler-audit` command is actually run.
  gem "bundler-audit", require: false
  # `gem "brakeman", require: false` adds a static-analysis security
  # scanner for Rails apps — it reads the app's own source code (without
  # running it) looking for common vulnerability patterns like SQL
  # injection or mass assignment. `require: false` for the same reason.
  gem "brakeman", require: false
  # `gem "rubocop-rails-omakase", require: false` adds the Omakase style
  # rule set that .rubocop.yml (see that file) loads via `inherit_gem:` —
  # without this gem present, RuboCop would fail to find those rules at
  # all. `require: false` since RuboCop loads its own config separately,
  # not via a plain top-level `require`.
  gem "rubocop-rails-omakase", require: false
  # `end` closes the `group :development, :test do` block opened above.
end

# Blank line — pure visual separation between group blocks.

# `group :test do ... end` — same mechanism as above, but scoped to ONLY
# the test environment (not development too).
group :test do
  # Comment (pre-existing) explaining WHY this specific gem is needed: a
  # future Minitest 6 release is expected to remove `Mock`/`Object#stub`
  # from its core library; this gem republishes that same functionality
  # separately, so code that stubs things like Faraday/network calls in
  # tests keeps working regardless of which Minitest version is installed.
  # Minitest 6 dropped Mock/Object#stub from core — this is the same code,
  # published separately, so stubbing Faraday/network calls in tests works.
  gem "minitest-mock"
  # `end` closes the `group :test do` block opened above.
end

# Blank line — pure visual separation.

# `group :development do ... end` — scoped to ONLY the development
# environment.
group :development do
  # `gem "web-console"` adds an interactive Ruby console embedded directly
  # into error pages shown in the browser during development — when an
  # unhandled exception occurs locally, you get a live REPL at the point of
  # failure right in the error page, instead of only a stack trace.
  gem "web-console"
  # `end` closes the `group :development do` block opened above.
end
