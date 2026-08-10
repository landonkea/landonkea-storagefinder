# Background for a novice: Rails apps run in one of several "environments"
# at a time, development (what you use while coding locally), test (used
# only while running automated tests, see config/environments/test.rb), and
# production (the real, live version actual users use, see
# config/environments/production.rb). Which environment is active is
# controlled by the RAILS_ENV environment variable; it defaults to
# "development" when nothing else is set, which is why `bin/rails server`
# run on a laptop uses THIS file's settings without any extra configuration.
# Settings here only take effect while RAILS_ENV is "development", they
# override whatever config/application.rb set for the same option, but only
# in this one environment.

# `require` loads a Ruby standard-library/gem file by searching Ruby's load
# path (as opposed to `require_relative`, used in config/application.rb,
# which loads a file by a path relative to the current file). This specific
# require pulls in Rails' "core extension" that adds convenience methods
# like `.days`/`.hours` onto plain Ruby Integers (e.g. `2.days`), used
# further down in this file to compute a cache duration.
require "active_support/core_ext/integer/time"

# Blank line, purely visual spacing, has no effect on Ruby.

# `Rails.application.configure do ... end` opens a block where `config` (a
# special object holding every setting for the whole app) can be modified.
# Rails runs this block automatically at boot, but ONLY when RAILS_ENV is
# "development", the rest of this file is skipped entirely otherwise.
Rails.application.configure do
  # A comment (left by Rails' generator) explaining that everything set
  # inside this block overrides the equivalent setting from
  # config/application.rb, for this environment only.
  # Settings specified here will take precedence over those in config/application.rb.

  # A comment explaining the setting below: normally, changing a `.rb` file
  # while a Rails server is running requires restarting that server before
  # the change takes effect. `config.enable_reloading = true` turns ON
  # Rails' code-reloading system instead, Rails watches your source files
  # and, on the very next incoming request after a file changes, silently
  # re-loads just the changed classes, without you needing to restart
  # anything. This is convenient for local development but has a real
  # runtime cost, which is why it's turned OFF in production (see
  # config/environments/production.rb).
  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # A comment explaining the setting below: "eager loading" means Rails
  # loads (via `require`) every single app file up front, immediately at
  # boot, rather than lazily the first time each class is actually
  # referenced (which is what Zeitwerk's autoloading normally does, see
  # config/application.rb's AUTOLOADING section for the full explanation of
  # autoloading itself). Eager loading makes BOOT slower but each individual
  # request slightly faster and more predictable (nothing needs to be
  # loaded mid-request). `false` here means development skips eager loading
  #, fast restarts matter more than per-request speed while coding.
  # Do not eager load code on boot.
  config.eager_load = false

  # A comment explaining the setting below: when an unhandled error/
  # exception occurs while handling a request, Rails can either show a
  # generic "Something went wrong" page (as production should, so real
  # visitors never see internal details) or Rails' own detailed debug page
  # (full backtrace, local variable values, etc). `true` here means always
  # show the detailed page, useful while developing, since you're both the
  # developer and the only person who'll ever see it.
  # Show full error reports.
  config.consider_all_requests_local = true

  # A comment explaining the setting below: "server timing" is a browser
  # developer-tools feature (the standard `Server-Timing` HTTP response
  # header) that reports how long different phases of handling a request
  # took (e.g. time spent in the database vs. rendering a view) directly in
  # the browser's Network tab. `true` turns on Rails sending that header.
  # Enable server timing.
  config.server_timing = true

  # A comment (left by Rails' generator) explaining the `if`/`else` block
  # below: it introduces "Action Controller caching" (a feature that can
  # cache whole rendered fragments of a page so they don't need to be
  # regenerated on every request) and how to toggle it locally.
  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  # `if` starts a conditional: the code in the following block only runs
  # when the condition on this line is true. `Rails.root` is this app's
  # root directory as a path object; `.join("tmp/caching-dev.txt")` builds
  # the full path to a specific marker file inside tmp/; `.exist?` is a
  # method (from Ruby's Pathname/File classes) returning true only if a
  # file actually exists at that path right now. Running `bin/rails
  # dev:cache` toggles this marker file's presence, so caching in
  # development can be flipped on/off without restarting or editing code.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    # If the marker file exists: turn ON Action Controller's fragment/page
    # caching feature for this dev server process.
    config.action_controller.perform_caching = true
    # Also make Rails log, in detail, WHEN a cached fragment is read from
    # cache vs. freshly rendered, useful for understanding caching
    # behavior while developing/debugging it.
    config.action_controller.enable_fragment_cache_logging = true
    # Sets an HTTP response header telling browsers to cache Rails' own
    # statically-served files (from public/) for a while. `{ "cache-control"
    # => "public, max-age=#{2.days.to_i}" }` is a Ruby Hash literal (a
    # header name mapped to its value); the value string uses STRING
    # INTERPOLATION (`#{...}` inside double quotes gets replaced with the
    # result of evaluating the Ruby expression inside it) to compute
    # `2.days.to_i`, `2.days` is an ActiveSupport::Duration representing
    # two days, and `.to_i` converts it to a plain integer number of
    # seconds, producing a literal string like "public, max-age=172800".
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    # If the marker file does NOT exist: leave Action Controller caching
    # turned off, which is the normal/default state for local development
    # (so you always see freshly rendered content while coding).
    config.action_controller.perform_caching = false
  end
  # `end` closes the `if ... else ... end` conditional started above.

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: `config.cache_store` chooses
  # WHERE Rails.cache (the app's general-purpose cache, e.g. used by the
  # geocoder gem's config/initializers/geocoder.rb) stores its data.
  # `:memory_store` keeps cached values in this process's own RAM, simple,
  # needs no extra services, but is wiped whenever the dev server restarts
  # and isn't shared between multiple processes.
  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: Active Storage (Rails' file-
  # upload framework) needs to know WHICH named service configuration from
  # config/storage.yml to actually use. `:local` is a Ruby Symbol selecting
  # the "local" entry in that file, which, per storage.yml's own comments
  #, stores uploaded files as plain files on this machine's own disk,
  # under the app's storage/ directory, rather than a cloud service like S3.
  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: normally, if Action Mailer
  # (Rails' email-sending framework) fails to actually deliver an email
  # (e.g. no mail server configured locally), it raises a Ruby exception
  # that would crash whatever code tried to send it. `false` here means
  # delivery failures are silently ignored instead, convenient locally,
  # since most developers don't have a working SMTP server configured on
  # their laptop, and a failed test email shouldn't crash the whole app.
  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: Action Mailer templates (the
  # views used to render email bodies) can also be cached like normal view
  # templates. `false` disables that caching, so editing a mailer template
  # and re-triggering an email shows the change immediately, matching how
  # `config.enable_reloading = true` above behaves for regular views.
  # Make template changes take effect immediately.
  config.action_mailer.perform_caching = false

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: when Action Mailer builds a full
  # URL inside an email body (e.g. a link back into the app), it can't infer
  # a hostname from an incoming web request the way a controller can,
  # sending an email isn't triggered by a browser visiting a URL, so the
  # host (and, here, port) must be configured explicitly. `{ host:
  # "localhost", port: 5555 }` is a Ruby Hash literal using symbol-key
  # shorthand (`host:` is shorthand for `:host =>`); port 5555 matches the
  # port this app's dev server actually listens on (see start.sh, referenced
  # elsewhere in this app's config, e.g. config/initializers/mdns.rb).
  # Set localhost to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "localhost", port: 5555 }

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: Rails periodically prints
  # "deprecation warnings", notices that some API currently being used will
  # be removed in a future Rails version, so you can fix them before
  # upgrading breaks anything. `:log` (a Symbol, one of a few valid choices
  # for this setting) sends those warnings into the normal Rails log file/
  # console output, rather than e.g. stderr or being silently ignored.
  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: if the database schema has
  # pending migrations (changes described in db/migrate/ that haven't been
  # applied to the actual database yet), `:page_load` makes Rails show a
  # dedicated "pending migrations" error page the very next time any page is
  # loaded, instead of letting a confusing, unrelated database error happen
  # partway through handling the request.
  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: `true` makes Active Record
  # (Rails' database layer) include, in the log, exactly which line of your
  # OWN application code triggered each SQL query, handy for tracking down
  # where a slow or unexpected query is coming from, at the cost of a bit of
  # extra logging overhead (acceptable while developing).
  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: `true` makes Active Record
  # append a small SQL comment (e.g. naming the controller/action) onto the
  # end of every SQL query it logs, similar purpose to the setting above,
  # giving more context about WHERE in the app each logged query came from.
  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: similar to the database-query
  # logging above, but for Active Job, `true` logs, for each background job
  # that gets enqueued, which line of application code enqueued it.
  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: similarly, `true` logs which
  # line of application code triggered an HTTP redirect response, making it
  # easier to trace where in the code an unexpected redirect came from.
  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: normally Rails logs a line for
  # every single request, including requests for static asset files (CSS,
  # JS, images). `true` here suppresses ("quiets") log lines specifically
  # for asset requests, keeping the development log focused on actual page
  # requests instead of being cluttered with dozens of asset-fetch lines.
  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # This line starts with `#`, so it (and the comment above explaining it)
  # are both inactive, Ruby ignores them entirely, they're not real code.
  # If the setting below were uncommented, it would make Rails raise a hard
  # error whenever an I18n (internationalization/translation) lookup can't
  # find a matching translation string, instead of silently rendering a
  # "translation missing" placeholder, see config/locales/en.yml for where
  # translations actually live.
  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: `true` makes Rails annotate
  # every rendered view's HTML output with an extra HTML comment naming
  # which exact template/partial file produced that section of the page,
  # handy while developing for figuring out which file to edit to change a
  # given piece of a page, at the cost of slightly noisier rendered HTML
  # (acceptable, even useful, in development; this is NOT enabled in
  # production, see config/environments/production.rb).
  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # This line starts with `#`, so it (and its explanatory comment above) are
  # inactive example code, not real config. If uncommented, it would disable
  # Action Cable's CSRF-style protection that normally rejects WebSocket
  # connection attempts originating from a different site, useful only if
  # you specifically need to test cross-origin WebSocket connections.
  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: `true` makes Rails raise an
  # error if a controller's `before_action`/`after_action` callback
  # specifies `only:`/`except:` options naming an action that doesn't
  # actually exist on that controller, catching a typo (e.g. referencing a
  # renamed or deleted controller action) as a loud, obvious failure rather
  # than the callback silently just never running.
  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Blank line, purely visual spacing, has no effect on Ruby.

  # This line starts with `#`, so it's an inactive example, not real code.
  # If uncommented, it would make every file Rails generators create (via
  # `bin/rails generate`) automatically get run through RuboCop's auto-
  # correction (a Ruby code-style linter/formatter) right after being
  # written.
  # Apply autocorrection by RuboCop to files generated by `bin/rails generate`.
  # config.generators.apply_rubocop_autocorrect_after_generate!

  # Blank line, purely visual spacing, has no effect on Ruby.

  # A comment explaining the block of lines below: by default, Rails only
  # accepts requests whose HTTP "Host" header matches a small safe default
  # list (as a security measure called DNS-rebinding protection). Because
  # this app is meant to be reachable from other devices on the same local
  # network, not just from "localhost", its allowed hostname list needs
  # to be widened to include the LAN mDNS hostname and typical private IP
  # ranges. See config/initializers/mdns.rb for the mDNS (Bonjour/Avahi)
  # announcement feature that makes the storagefinder.local name resolve on
  # the network in the first place.
  # Allow requests from storagefinder.local and any .local mDNS hostname, plus LAN IPs.
  # `config.hosts` is an Array of allowed hostnames/patterns; `<<` is Ruby's
  # array-append ("shovel") operator, adding one more allowed entry each
  # time it's used. This first entry is a plain String, the exact literal
  # hostname "storagefinder.local".
  config.hosts << "storagefinder.local"
  # This entry is a Ruby Regexp (regular expression) literal, written
  # between forward slashes `/ /`, a pattern-matching mini-language rather
  # than an exact string. `.*\.local` matches ANY hostname ending in
  # ".local" (`.` inside a regex normally means "any character," so `\.`,
  # backslash-escaped, means a LITERAL dot; `.*` means "zero or more of any
  # character" beforehand), covering every device's mDNS hostname on the
  # LAN, not just this app's own.
  config.hosts << /.*\.local/
  # Another Regexp, this one matching any IP address in the 192.168.x.x
  # private range (a very common home-router default subnet). `\d+` matches
  # "one or more digits"; `\.` again means a literal dot (not "any
  # character"). This lets devices reach the app by raw IP address too, not
  # just by hostname.
  config.hosts << /192\.168\.\d+\.\d+/
  # Matches any IP address in the 10.x.x.x private range, another entire
  # block of addresses reserved for private/local networks (larger than the
  # 192.168.x.x range above, often used on bigger or business networks).
  config.hosts << /10\.\d+\.\d+\.\d+/
  # Matches any IP address in the 172.16.0.0–172.31.255.255 private range,
  # the third and last block of addresses reserved for private networks.
  # `(1[6-9]|2\d|3[01])` is a Regexp GROUP with alternatives separated by
  # `|` ("or"): it matches 16-19 (`1[6-9]`), OR 20-29 (`2\d`), OR 30-31
  # (`3[01]`), together, exactly the second-octet range that RFC 1918
  # reserves for this private block.
  config.hosts << /172\.(1[6-9]|2\d|3[01])\.\d+\.\d+/

  # Blank line, purely visual spacing, has no effect on Ruby.

  # Bullet (see Gemfile's :development group) watches every ActiveRecord
  # query issued during a request/console session and flags N+1 queries,
  # a loop that issues one extra DB query per record instead of eager-
  # loading the association up front, plus unused eager-loads and missing
  # counter caches. `config.after_initialize do ... end` defers this block
  # until Rails has finished booting, which is Bullet's own documented
  # requirement (its config methods aren't available any earlier).
  config.after_initialize do
    # Turns Bullet on at all; every other Bullet setting below is a no-op
    # while this is false.
    Bullet.enable = true
    # Logs warnings to Rails.root/log/bullet.log, a dedicated log file just
    # for Bullet's findings, so they're easy to review after exercising the
    # app without digging through the normal development log.
    Bullet.bullet_logger = true
    # Also writes warnings into the normal Rails log
    # (log/development.log), so they show up alongside everything else
    # without needing to open a second file.
    Bullet.rails_logger = true
    # Pops up a JavaScript `alert()` in the browser the moment Bullet
    # detects a problem on a rendered page, the most immediately visible
    # option while manually clicking around during development.
    Bullet.alert = true
    # Logs warnings to the browser's own console.log as well, for cases
    # where a popped-up alert() would be disruptive (e.g. many warnings on
    # one page) but the browser devtools console is still open.
    Bullet.console = true
    # Adds a small floating footer to the bottom-left of every page
    # listing the queries Bullet flagged for that request, an
    # always-visible summary that doesn't require opening devtools or a
    # log file at all.
    Bullet.add_footer = true
  end
end
# `end` closes the `Rails.application.configure do` block opened near the
# top of the file, every setting above only applies while running in the
# development environment.
