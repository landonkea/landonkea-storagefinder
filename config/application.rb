# =============================================================================
# WHAT IS config/application.rb?
# =============================================================================
# This is the main configuration file for the whole Rails application. Unlike
# the files in config/environments/ (development.rb, production.rb, test.rb,
# each of which only applies when RAILS_ENV matches that file's name), the
# settings in THIS file are loaded and applied for EVERY environment, every
# single time the app boots (e.g. `bin/rails server`, `bin/rails console`,
# running the test suite, a background job worker, etc). Environment-specific
# files are processed AFTER this one and can override anything set here.
#
# This file also declares which pieces of Rails ("frameworks") to load and
# configures "autoloading", Rails' system (called Zeitwerk) for automatically
# finding and loading this app's own Ruby classes/modules from files in app/
# and lib/, without writing a manual `require` for each one. See the
# AUTOLOADING section further down for a full explanation of how that works
# and why this particular app customizes it.
# =============================================================================

# `require_relative` loads another Ruby file, given a path relative to THIS
# file's own location on disk (as opposed to plain `require` below, which
# searches Ruby's/Bundler's standard load path for gems). `"boot"` refers to
# config/boot.rb, sitting right next to this file, Ruby automatically
# appends the ".rb" extension, so it isn't written explicitly. boot.rb sets
# up Bundler (the gem-dependency manager) before anything else here runs.
require_relative "boot"

# Blank line, purely visual spacing, has no effect on Ruby.

# Plain `require "rails"` loads the core Rails framework/gem itself, making
# top-level constants like `Rails` and `Rails::Application` (used further
# below) available to the rest of this file.
require "rails"
# A plain comment (not code, Ruby ignores anything after a `#`) introducing
# the block of `require` lines below: Rails ships as several independent
# pieces ("frameworks"), each loaded separately here so an app could, in
# principle, opt out of any it doesn't need. None are opted out of below.
# Pick the frameworks you want:
# Loads Active Model, the framework providing validations, callbacks, and
# other object-style behaviors shared by both database-backed and
# non-database-backed classes. "railtie" is Rails' term for the small hook
# file a framework provides so Rails' own boot sequence knows how to wire it
# into the app.
require "active_model/railtie"
# Loads Active Job, Rails' framework for defining and enqueueing background
# jobs (work that runs outside the normal request/response cycle, e.g.
# crawling a website or sending an email). This app's own job classes build
# on top of it; see the BACKGROUND JOBS section below for which backend
# actually executes them.
require "active_job/railtie"
# Loads Active Record, Rails' Object-Relational Mapper (ORM): the layer
# that lets plain Ruby classes (e.g. a `Unit` or `Company` model somewhere
# under app/models) read and write rows in the SQL database without hand-
# writing SQL.
require "active_record/railtie"
# Loads Active Storage, Rails' framework for attaching and managing
# uploaded files (images, documents, etc). See config/storage.yml for the
# actual storage backend(s) it's configured to use per environment.
require "active_storage/engine"
# Loads Action Controller, the framework that turns an incoming HTTP
# request into a call to one of this app's controller classes (the "C" in
# the MVC, Model/View/Controller, pattern Rails is built around).
require "action_controller/railtie"
# Loads Action Mailer, Rails' framework for composing and sending OUTGOING
# email.
require "action_mailer/railtie"
# Loads Action Mailbox, Rails' framework for receiving and routing INCOMING
# email (the opposite direction from Action Mailer above).
require "action_mailbox/engine"
# Loads Action Text, Rails' framework for rich-text ("WYSIWYG") content
# stored as an attribute on a model.
require "action_text/engine"
# Loads Action View, the framework responsible for rendering templates
# (ERB files, etc.) into the actual HTML sent back to a browser (the "V" in
# MVC).
require "action_view/railtie"
# Loads Action Cable, Rails' framework for WebSockets/real-time features;
# see config/cable.yml and the ACTION CABLE section below for how its
# adapter is chosen per environment.
require "action_cable/engine"
# This line begins with `#`, so it's a comment, not executable code, an
# inactive example left by Rails' project generator. If uncommented, it
# would load `rails/test_unit/railtie`, wiring Rails' built-in `bin/rails
# test` task and related generators into the app. Left commented out here;
# nothing in this file tells you on its own whether Minitest is loaded some
# other way instead.
# require "rails/test_unit/railtie"

# Blank line, purely visual spacing, has no effect on Ruby.

# A plain comment explaining the line below: it loads every gem listed in
# this app's Gemfile (third-party libraries), INCLUDING gems Gemfile
# restricts to specific environments via its own `group :test do ... end`
# style blocks.
# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
# `Bundler` is the gem-dependency-management library (already required
# indirectly via boot.rb). `.require` is a Bundler method that loads (via
# Ruby's own `require`) every gem Bundler knows about for the given
# group(s). `Rails.groups` returns an Array of Symbols naming which Gemfile
# groups are relevant to the CURRENT environment (e.g. `[:default,
# :development]`). The leading `*` is Ruby's "splat" operator: it expands
# that Array into separate individual arguments passed to `.require`,
# rather than passing the whole Array in as one single argument.
Bundler.require(*Rails.groups)

# Blank line, purely visual spacing, has no effect on Ruby.

# `module` opens a Ruby Module, a named namespace grouping related
# classes/constants together so their names don't collide with unrelated
# code elsewhere in the app or in gems. "Storagefinder" is this app's own
# top-level namespace, generated automatically from the app's name when the
# project was first created with `rails new`.
module Storagefinder
  # `class Application < Rails::Application` defines a class named
  # `Application` nested inside the `Storagefinder` module above (so its
  # full name, as referenced elsewhere, is `Storagefinder::Application`).
  # `< Rails::Application` means this class INHERITS from Rails' own
  # `Rails::Application` class, automatically gaining all of Rails' built-in
  # application behavior, everything below customizes/extends it. Rails
  # specifically looks for a class matching this "Module::Application
  # inheriting from Rails::Application" shape to represent "the app" as one
  # single object (available elsewhere as `Rails.application`).
  class Application < Rails::Application
    # A comment (left by Rails' generator) explaining the line below: Rails
    # ships with sane default settings, but those defaults occasionally
    # change between Rails versions. `load_defaults` locks this app to
    # behave according to the defaults AS OF one specific named Rails
    # version, so simply upgrading the installed `rails` gem later doesn't
    # silently change this app's behavior, that number gets bumped
    # deliberately, on its own schedule, after reviewing what changed.
    # Initialize configuration defaults for originally generated Rails version.
    # `config` here is a special reader available inside this class body,
    # giving access to the application's configuration object, the same
    # kind of object referred to elsewhere in the codebase (e.g. in
    # config/initializers/*.rb files) as `Rails.application.config`.
    # `.load_defaults` is a method call on it; `8.1` is a Ruby Float literal
    # naming the Rails version (Rails 8.1) whose default behaviors this app
    # should use.
    config.load_defaults 8.1

    # Blank line, purely visual spacing, has no effect on Ruby.

    # A comment (left by Rails' generator) explaining the `ignore:` option
    # demonstrated on the line below.
    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `config.autoload_lib` tells Rails to autoload Ruby files from this
    # app's top-level `lib/` directory the same way it autoloads `app/`
    # (Rails does NOT autoload `lib/` by default, for historical reasons).
    # `ignore:` is a keyword argument, Ruby's syntax for passing a named
    # option into a method call, whose value here is `%w[assets tasks]`.
    # `%w[...]` is Ruby's "word array" literal shorthand: it builds an Array
    # of Strings by splitting on whitespace, so `%w[assets tasks]` means
    # exactly the same thing as writing `["assets", "tasks"]`, just with
    # less typing and no quote marks needed. This tells Rails NOT to
    # autoload anything under lib/assets/ or lib/tasks/, those directories
    # hold non-class files (static asset files, Rake task definitions) that
    # Zeitwerk (Rails' autoloader, explained fully in the AUTOLOADING
    # section below) would otherwise raise a boot-time error trying to
    # interpret as class/module definitions.
    config.autoload_lib(ignore: %w[assets tasks])

    # Blank line, purely visual spacing, has no effect on Ruby.

    # A multi-line comment (left by Rails' generator) explaining that
    # further app-wide settings belong in this class body, and that any of
    # them can be overridden per-environment by files in
    # config/environments/, which load AFTER this file (as explained in the
    # box comment at the very top of this file).
    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # The two lines below both start with `#`, so they are inactive example
    # comments, not real code. If the first were uncommented, it would set
    # this app's default time zone to US Central time, though notice this
    # app actually sets a DIFFERENT, ACTIVE `config.time_zone = "UTC"` a bit
    # further down in this same file (see the TIME section below), so this
    # commented-out example doesn't reflect what the app really does. If the
    # second were uncommented, it would add a folder named "extras" at the
    # app's root directory to the list of directories Rails eager-loads
    # (loads every file from, up front, at boot), `<<` is Ruby's array-
    # append ("shovel") operator, and `Rails.root.join("extras")` builds the
    # absolute path to that folder.
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Blank line, purely visual spacing, has no effect on Ruby.

    # A comment explaining the line below: Rails can auto-generate a system
    # test file (a full, simulated-browser end-to-end test) alongside other
    # files whenever a `bin/rails generate` command creates something (e.g.
    # generating a scaffold). Setting this to `nil` (Ruby's "nothing"/
    # absence-of-a-value object) turns that particular auto-generation off,
    # so running generators in this app won't create that boilerplate.
    # Don't generate system test files.
    config.generators.system_tests = nil

    # Blank line, purely visual spacing, has no effect on Ruby.

    # A row of `-` characters inside a comment is purely a visual section
    # divider for human readers, it has no effect on Ruby, and the same is
    # true of every other "----" or "====" style comment line in this file.
    # ---------------------------------------------------------------------------
    # AUTOLOADING
    # ---------------------------------------------------------------------------
    # This section customizes Zeitwerk, the autoloading system Rails has
    # used since Rails 6 (loaded implicitly as part of Rails core, not one
    # of the explicit `require` lines above). Zeitwerk's whole job: given a
    # file path like app/models/unit.rb, automatically work out, WITHOUT
    # anyone writing a manual `require`, that it should define a constant
    # named `Unit`, and load that exact file the first time `Unit` is
    # referenced anywhere in the running app. This file-path-to-constant-
    # name mapping follows a strict, consistent convention: each level of
    # subdirectory nesting under app/ (or under lib/, once autoloaded via
    # config.autoload_lib above) normally becomes one level of Ruby module
    # namespacing, and each file is expected to define exactly one constant
    # named after that file. For example, a file at
    # app/services/billing/invoice.rb is expected by Zeitwerk to define
    # `Billing::Invoice`, the "billing" subdirectory maps to a wrapping
    # `Billing` module around the `Invoice` class inside it.
    #
    # This app has two subdirectories under app/services/, recon/ and
    # alerting/, whose files were NOT written following that namespacing
    # convention (e.g. a file living at
    # app/services/recon/recon_service.rb defines a plain top-level class
    # named `ReconService`, not the `Recon::ReconService` Zeitwerk would
    # otherwise expect from that path). Left unconfigured, Zeitwerk would
    # raise a boot-time error complaining the file didn't define the
    # constant it expected there. "Collapsing" a directory tells Zeitwerk:
    # treat files sitting directly inside this one specific directory as if
    # they instead lived one level higher up (i.e. drop the extra namespace
    # that directory would otherwise contribute), without changing how any
    # OTHER, sibling directory is autoloaded.
    # Collapse subdirectories that don't use namespacing.
    # This means ReconService (not Recon::ReconService) and
    # AlertDeliveryService (not Alerting::AlertDeliveryService)
    # `initializer` is a `Rails::Application` class method that registers a
    # named block of setup code to run at a specific point during Rails'
    # boot sequence, rather than running immediately as this class body is
    # first read. Its first argument, `"storagefinder.autoload_collapse"`,
    # is simply a unique String name/identifier for this particular
    # initializer (the "app_name.description" naming convention avoids
    # colliding with initializer names Rails or other gems register).
    # `before: :bootstrap_hook` is a keyword argument telling Rails to run
    # this block BEFORE Rails' own built-in `:bootstrap_hook` initializer,
    # `:bootstrap_hook` is a Symbol (a lightweight, named-value type written
    # with a leading colon) naming one specific step of Rails' internal
    # initialization sequence. This needs to happen early, before Zeitwerk
    # starts eager/autoloading anything, otherwise the collapse/ignore
    # configuration below would be registered too late to have any effect.
    # `do ... end` opens a block: a chunk of code passed as an argument to
    # `initializer`, to be executed later (at the point described above)
    # rather than immediately when this line is first read.
    initializer "storagefinder.autoload_collapse", before: :bootstrap_hook do
      # `Rails.autoloaders` gives access to Zeitwerk's autoloader object(s);
      # `.main` is the primary one used for app/ and lib/ (Rails separately
      # maintains a smaller "once" autoloader for a few special engine
      # cases, not relevant here). `.collapse(...)` tells that autoloader to
      # apply the "collapsing" behavior explained above, for the exact
      # directory path given as its argument. `"#{config.root}/app/services/recon"`
      # is a Ruby String built using STRING INTERPOLATION: the `#{...}`
      # inside a double-quoted string gets replaced with the result of
      # evaluating the Ruby expression written inside it. `config.root` is
      # this app's root directory, as a path-like object; the whole
      # expression therefore builds the full absolute path to
      # app/services/recon on disk.
      Rails.autoloaders.main.collapse("#{config.root}/app/services/recon")
      # Same idea as the line directly above, but collapsing
      # app/services/alerting instead, so files there also skip the extra
      # `Alerting::` namespace Zeitwerk would otherwise expect.
      Rails.autoloaders.main.collapse("#{config.root}/app/services/alerting")
      # A plain comment (not code) noting, for anyone reading this block,
      # that a THIRD services subdirectory, app/services/companies/, is
      # deliberately NOT collapsed here, because code living there DOES
      # want the extra `Companies::` namespace (e.g. a class named
      # `Companies::BaseParser`). Calling this out explicitly heads off
      # someone "helpfully" adding a third collapse call for it later.
      # companies/ is NOT collapsed, Companies::BaseParser etc. is intentional

      # Blank line, purely visual spacing, has no effect on Ruby.

      # A comment explaining the line below: TEMPLATE.rb is a file meant to
      # be manually copied and renamed by a developer as a starting point
      # for writing a new company-specific parser class, it is not itself
      # a real, loadable parser. Because its filename ("TEMPLATE.rb")
      # doesn't match any real constant name Zeitwerk would expect from
      # that location (it breaks the "one file defines one identically-
      # named constant" convention Zeitwerk enforces, contrast with the
      # `Companies::YourCompanyName` example this comment gives, which
      # WOULD match a correctly-named file), Zeitwerk would raise a boot-
      # time error if it ever attempted to autoload this exact file.
      # TEMPLATE.rb is a copy-paste template, not a real parser, it doesn't
      # follow Zeitwerk's one-file-one-constant convention (Companies::YourCompanyName
      # in a file named TEMPLATE.rb), so exclude it from autoloading entirely.
      # `.ignore(...)` tells Zeitwerk to skip this exact file path entirely
      # , never attempt to autoload it as a constant at all, which is a
      # stronger exclusion than `.collapse` above (`.collapse` still
      # autoloads files in that directory, just under a flattened/different
      # namespace; `.ignore` means Zeitwerk pretends this file doesn't
      # exist at all).
      Rails.autoloaders.main.ignore("#{config.root}/app/services/companies/TEMPLATE.rb")
    end
    # `end` closes the `initializer "storagefinder.autoload_collapse" do`
    # block opened above, everything between there and here only runs
    # once, at the specific point during boot described by
    # `before: :bootstrap_hook`, not every time this class body is read.

    # Blank line, purely visual spacing, has no effect on Ruby.

    # ---------------------------------------------------------------------------
    # TIME
    # ---------------------------------------------------------------------------
    # `config.time_zone` sets the time zone Rails uses when displaying and
    # interpreting times throughout the app (e.g. via the `Time.zone.now`
    # helper Rails adds), independent of whatever time zone the underlying
    # server/OS system clock itself is set to. `"UTC"` (Coordinated
    # Universal Time, the time-zone-independent global reference standard)
    # is a common choice for apps that want to store and compare times
    # consistently everywhere internally, converting to a specific local
    # time zone only when actually DISPLAYING a time to a human, this
    # avoids a whole class of daylight-saving-time and multi-timezone bugs.
    config.time_zone = "UTC"

    # Blank line, purely visual spacing, has no effect on Ruby.

    # ---------------------------------------------------------------------------
    # BACKGROUND JOBS
    # ---------------------------------------------------------------------------
    # A comment explaining the setting below: it names which background-job
    # backend ("adapter") Active Job (loaded near the top of this file) uses
    # to actually run jobs that get enqueued. `:async` is Rails' own built-
    # in adapter, which runs jobs on a thread pool WITHIN the same running
    # Ruby process (the same `bin/rails server` process), no separate
    # worker process, and no extra infrastructure like Redis (an in-memory
    # data store some job backends use to hold a shared queue) or Postgres
    # (a SQL database the GoodJob gem specifically requires) is needed. The
    # tradeoff, as the comment notes: if the process restarts or crashes,
    # any jobs still waiting in memory are simply lost, judged acceptable
    # here because this is a small, single-machine app.
    # In-process async adapter, no Redis or Postgres needed for a
    # single-machine local app backed by SQLite (GoodJob requires Postgres,
    # so it isn't usable here). This is the APP-WIDE DEFAULT, in effect for
    # development and any environment that doesn't override it. Production
    # and staging DO override it (see config/environments/production.rb and
    # config/environments/staging.rb) to `:solid_queue` instead, because
    # the scheduled-crawl feature (see config/recurring.yml and
    # app/jobs/scheduled_crawl_check_job.rb) needs a real recurring-task
    # dispatcher that keeps checking the clock on its own, something the
    # in-process `:async` adapter, which only ever runs a job when THIS
    # process itself enqueues one, cannot do. The test environment also
    # overrides this (see config/environments/test.rb, which sets `:test`).
    config.active_job.queue_adapter = :async

    # Blank line, purely visual spacing, has no effect on Ruby.

    # ---------------------------------------------------------------------------
    # ACTION CABLE
    # ---------------------------------------------------------------------------
    # A comment explaining the setting below: similarly to Active Job above,
    # this picks Action Cable's in-process ("async") WebSocket adapter, see
    # config/cable.yml's development section for a fuller explanation of
    # what the async adapter actually does and its single-process
    # limitation.
    # Async adapter, no Redis needed for a single-machine local app
    # `config.action_cable.cable` is assigned a Ruby Hash literal here,
    # `{ "adapter" => "async" }`, using STRING keys with the `=>` "hash
    # rocket" syntax (rather than the shorter `adapter:` symbol-key
    # shorthand), because this exact shape mirrors how Rails parses
    # config/cable.yml's own per-environment settings, so either source can
    # populate this same setting in a consistent format. NOTE: this line
    # applies unconditionally in EVERY environment because it lives in this
    # shared config/application.rb rather than in one environment-specific
    # file.
    #
    # FIXED (previously a real bug): this line used to hardcode the async
    # adapter for EVERY environment, including production, which silently
    # overrode config/cable.yml's own production section (`adapter:
    # solid_cable`, wired to a dedicated database connection and persistent
    # Docker volume). Rails only falls back to reading config/cable.yml when
    # `config.action_cable.cable` is left unset; setting it explicitly here,
    # unconditionally, meant cable.yml's production block was dead
    # configuration, production would have used the in-process async
    # adapter no differently than development, defeating the point of
    # solid_cable (multi-process/multi-worker WebSocket broadcasting). This
    # line has been removed so each environment's config/cable.yml section
    # actually takes effect as designed. (In practice this app currently
    # runs Puma with a single worker process, so async would have worked by
    # accident, but the override would have silently broken WebSocket
    # broadcasting the moment WEB_CONCURRENCY was ever raised above 1.)
  end
  # `end` closes the `class Application < Rails::Application` definition
  # opened above.
end
# `end` closes the `module Storagefinder` block opened at the very top of
# the file.
