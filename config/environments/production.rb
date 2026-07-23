# Background for a novice: Rails apps run in one of several "environments"
# at a time — development (local coding, see config/environments/
# development.rb), test (automated test runs, see config/environments/
# test.rb), and production (this file) — the real, live version actual
# users use. Which environment is active is controlled by the RAILS_ENV
# environment variable; StorageFinder's Kamal deploy (see config/deploy.yml)
# runs the app with RAILS_ENV=production inside its Docker container.
# Settings here only take effect while RAILS_ENV is "production" — they
# override whatever config/application.rb set for the same option, but only
# in this one environment.

# `require` loads a Ruby standard-library/gem file by searching Ruby's load
# path. This specific require pulls in Rails' "core extension" that adds
# convenience methods like `.days`/`.year` onto plain Ruby Integers (e.g.
# `1.year`) — used further down in this file to compute a cache duration.
require "active_support/core_ext/integer/time"

# Blank line — purely visual spacing, has no effect on Ruby.

# `Rails.application.configure do ... end` opens a block where `config` (a
# special object holding every setting for the whole app) can be modified.
# Rails runs this block automatically at boot, but ONLY when RAILS_ENV is
# "production" — the rest of this file is skipped entirely otherwise.
Rails.application.configure do
  # A comment (left by Rails' generator) explaining that everything set
  # inside this block overrides the equivalent setting from
  # config/application.rb, for this environment only.
  # Settings specified here will take precedence over those in config/application.rb.

  # A comment explaining the setting below: the opposite of development's
  # `config.enable_reloading = true`. `false` here means Rails never re-
  # checks whether a `.rb` file changed mid-run — once a class is loaded,
  # it stays loaded as-is for the lifetime of the running process. This is
  # both faster (no per-request "has this file changed?" filesystem checks)
  # and safer for production, where code SHOULDN'T change underneath a
  # running process anyway (a new deploy replaces the whole running
  # container instead — see config/deploy.yml).
  # Code is not reloaded between requests.
  config.enable_reloading = false

  # A comment explaining the setting below: the opposite of development's
  # `config.eager_load = false`. `true` here means every app file is loaded
  # up front at boot (see config/application.rb's AUTOLOADING section for
  # what "eager loading" vs. lazy autoloading means) — slower to start, but
  # every class is immediately ready to use for every request afterward,
  # and any class-loading error surfaces immediately at boot/deploy time
  # rather than unpredictably during a live request. The parenthetical note
  # ("ignored by Rake tasks") means one-off command-line tasks (`bin/rails
  # db:migrate`, etc.) skip eager loading regardless of this setting, since
  # they don't need to serve any requests.
  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: the opposite of development's
  # `config.consider_all_requests_local = true`. `false` here means real
  # visitors see a generic, non-technical error page when something goes
  # wrong, instead of Rails' detailed debug page (which would otherwise leak
  # internal details like file paths, variable values, and stack traces to
  # the public internet).
  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: "fragment caching" lets specific
  # chunks of a rendered view be cached and reused across requests, instead
  # of being re-rendered from scratch every time — `true` turns this feature
  # on for production, where the performance benefit matters most (unlike
  # development, where fresh-every-time rendering is more useful while
  # actively editing views).
  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: Rails' asset pipeline appends a
  # content-based "digest" (a short hash) to every compiled CSS/JS/image
  # asset's filename, so that if the file's content ever changes, its
  # generated filename/URL changes too — meaning it's always safe to tell
  # browsers to cache the OLD filename's content forever, since that exact
  # filename will never point at different content later. `{ "cache-control"
  # => "public, max-age=#{1.year.to_i}" }` is a Ruby Hash literal (header
  # name mapped to value); the value string uses STRING INTERPOLATION
  # (`#{...}` inside double quotes evaluates the Ruby expression inside it)
  # to compute `1.year.to_i` — `1.year` is an ActiveSupport::Duration
  # representing one year, `.to_i` converts it to a plain integer number of
  # seconds — producing a header value telling browsers "cache this for
  # (approximately) a year."
  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Blank line — purely visual spacing, has no effect on Ruby.

  # This line starts with `#`, so it's an inactive example, not real code —
  # if uncommented, it would tell Rails that static assets (images,
  # stylesheets, JavaScript) should be fetched from a separate host/domain
  # (a CDN, for example) rather than served from this same app server.
  # StorageFinder doesn't use a separate asset host, so this stays off.
  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: Active Storage (Rails' file-
  # upload framework) needs to know WHICH named service configuration from
  # config/storage.yml to actually use. `:local` selects the "local" entry
  # there, which stores uploaded files as plain files on this machine's own
  # disk — matching config/deploy.yml's persistent Docker volume mounted at
  # /rails/storage, so uploaded files survive across deploys/restarts.
  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Blank line — purely visual spacing, has no effect on Ruby.

  # This line starts with `#`, so it (and its explanatory comment above) are
  # inactive example code. If uncommented, it would tell Rails to assume
  # every incoming request already arrived over HTTPS, because a separate
  # reverse proxy in front of the app (not Rails itself) is the thing
  # actually terminating SSL/TLS encryption — relevant only if this app sat
  # behind such a proxy, e.g. Kamal's optional built-in proxy (see the
  # commented-out `proxy:` section in config/deploy.yml).
  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Blank line — purely visual spacing, has no effect on Ruby.

  # Another inactive example (starts with `#`). If uncommented, it would
  # make Rails itself enforce HTTPS: redirecting any plain-HTTP request to
  # HTTPS, adding the Strict-Transport-Security response header (which
  # tells browsers to always use HTTPS for this site from now on), and
  # marking cookies "secure" (only ever sent over HTTPS).
  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Blank line — purely visual spacing, has no effect on Ruby.

  # Another inactive example (starts with `#`), shown as a companion to
  # `config.force_ssl` immediately above: if BOTH were uncommented, this
  # line would carve out one exception to the forced-HTTPS-redirect rule
  # for the "/up" path specifically — that's Rails' built-in health-check
  # endpoint (see `config.silence_healthcheck_path` further below), and
  # some infrastructure health-checkers can't follow an HTTPS redirect, so
  # this lets that one path keep responding over plain HTTP.
  # `->(request) { request.path == "/up" }` is a Ruby "lambda" (an
  # anonymous, reusable mini-function) that takes one argument named
  # `request` and returns true only when the request's path is exactly
  # "/up".
  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the two lines below: in production, application
  # logs are written to STDOUT (the standard output stream) rather than a
  # log FILE, because that's the convention Docker/Kamal-based deployments
  # expect — `bin/kamal logs` (see the `aliases:` section of config/
  # deploy.yml) reads container logs from stdout, not from a file inside
  # the container.
  # Log to STDOUT with the current request id as a default log tag.
  # `config.log_tags = [ :request_id ]` is a Ruby Array containing one
  # Symbol; it tells Rails to prefix every log line for a given request
  # with that request's unique ID, making it possible to find every log
  # line belonging to one specific request even when many requests are
  # being handled/logged concurrently.
  config.log_tags = [ :request_id ]
  # `config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)` replaces
  # Rails' default logger (which normally writes to log/production.log)
  # with one that writes to `STDOUT` (Ruby's built-in constant representing
  # the standard output stream) instead, wrapped in
  # `ActiveSupport::TaggedLogging` so the `log_tags` setting above (like
  # the request ID) actually gets prefixed onto each log line.
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: controls HOW MUCH detail gets
  # logged — "debug" is the most verbose level and can include sensitive
  # request data, so it's normally reserved for troubleshooting rather than
  # left on permanently. `ENV.fetch("RAILS_LOG_LEVEL", "info")` reads the
  # RAILS_LOG_LEVEL environment variable if it's set (letting an operator
  # override the log level without editing/redeploying code — see the
  # commented-out `RAILS_LOG_LEVEL: debug` example in config/deploy.yml's
  # env section), falling back to the String `"info"` (a normal, moderate
  # level of detail) if that environment variable was never set at all —
  # that's what the second argument to `.fetch` (the "default value") does.
  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: Rails' built-in health-check
  # endpoint (the "/up" path, used by load balancers/monitoring/Kamal itself
  # to check the app is alive) would normally get logged like any other
  # request — but since it can be hit very frequently (e.g. every few
  # seconds), that would flood the logs with noise unrelated to real
  # traffic. Setting this silences logging specifically for that one path.
  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: the opposite of development's
  # `config.active_support.deprecation = :log`. `false` here means
  # deprecation warnings (notices that some Rails API in use will be
  # removed in a future version) are not reported/logged at all in
  # production — real users' logs shouldn't be cluttered with developer-
  # facing upgrade warnings; those are meant to be caught during
  # development/testing instead.
  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Blank line — purely visual spacing, has no effect on Ruby.

  # This multi-line comment is this app's OWN custom note (not Rails' stock
  # generated comment) explaining an intentional, non-default choice made
  # below: many Rails production setups use "Solid Cache" (a database-backed
  # cache) and "Solid Queue" (a database-backed job queue) so that cached
  # data/pending jobs survive a server restart and can be shared across
  # multiple server processes/machines. This app deliberately does NOT use
  # either — it runs as a single process on a single machine (a small,
  # self-hosted LAN app — see config/deploy.yml, which deploys to exactly
  # one server), so there's no second process to coordinate durable state
  # with, and the added complexity of those gems (which, per this comment,
  # aren't even installed) isn't worth it. The practical consequence: if
  # this production process restarts, in-memory cache entries and any job
  # still waiting to run are simply lost.
  # Use the same in-process cache store and job adapter as development.
  # This is a single-process, single-user LAN app — there's no second
  # process for a durable queue/cache to coordinate with, so the
  # solid_queue/solid_cache gems this used to reference (and never had
  # installed) aren't needed. Job state simply doesn't survive a restart.
  # `:memory_store` (matching development.rb) keeps Rails.cache entries in
  # this process's own RAM.
  config.cache_store = :memory_store
  # `:async` (matching config/application.rb's own already-active setting)
  # runs Active Job jobs on a thread pool inside this same process — see
  # config/application.rb's BACKGROUND JOBS section for the full
  # explanation. NOTE: this line re-states the exact same value
  # config/application.rb already sets for every environment, so this
  # specific line has no additional effect on its own — see this pass's
  # final "flagged issues" note.
  config.active_job.queue_adapter = :async

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the two lines below together: they document what
  # `raise_delivery_errors` would do if actually enabled (it's currently
  # commented out below, meaning Rails' DEFAULT for this setting is in
  # effect instead, not literally "false" as the comment's own wording
  # might suggest at a glance — see this pass's final "flagged issues" note
  # about this line specifically).
  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # This line begins with `#`, so it's inactive — not real code, just an
  # example left showing the syntax that WOULD control this behavior if
  # uncommented.
  # config.action_mailer.raise_delivery_errors = false

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: when Action Mailer builds a full
  # URL inside an email body (e.g. a link back into the app), it can't infer
  # a hostname from an incoming web request — sending an email isn't
  # triggered by a browser visiting a URL — so a host must be configured
  # explicitly. "example.com" is a placeholder-safe domain name (formally
  # reserved by IANA for documentation/example use) rather than this app's
  # real deployed hostname — see this pass's final "flagged issues" note,
  # since a real deployment would presumably want its actual domain here so
  # mailer-generated links work correctly for real recipients.
  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the commented-out block below: it shows the syntax
  # for configuring an actual outgoing SMTP (email-sending) server, needed
  # for Action Mailer to deliver real email in production. It stays
  # inactive here, meaning this app currently has no outgoing email server
  # configured at all.
  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # This whole block begins each line with `#`, so all of it is inactive
  # example code, not real config. If uncommented, `config.action_mailer.
  # smtp_settings` would be assigned a Ruby Hash literal (the `{` starts it,
  # spanning multiple lines until the matching `}`) configuring an SMTP
  # connection. `Rails.application.credentials.dig(:smtp, :user_name)`
  # would read a value out of this app's ENCRYPTED credentials file
  # (config/credentials.yml.enc — see that file's entry in the excluded-
  # files list of this pass's style guide) — `.dig` safely looks up a
  # nested key (`:smtp` then `:user_name` inside it) without raising an
  # error if an intermediate key is missing, returning `nil` instead.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: I18n (internationalization) is
  # Rails' translation system — see config/locales/en.yml. "Fallbacks" mean
  # that if a translation is missing for the currently active locale (e.g.
  # a Spanish translation hasn't been written yet for some text), I18n
  # falls back to trying `I18n.default_locale` (normally English) instead of
  # immediately showing a "translation missing" placeholder — `true` turns
  # this fallback behavior on.
  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: normally, running a database
  # migration locally also regenerates db/schema.rb (a snapshot file
  # describing the database's current structure) to match. In production,
  # migrations are expected to have already been tested and their resulting
  # schema.rb already committed to the repo beforehand — regenerating it
  # again automatically, on a live production server, during a live
  # deploy's migration step, is both unnecessary and (per Rails' own
  # convention) considered risky, so it's turned off here.
  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the setting below: when you inspect an Active
  # Record object in a console or log (e.g. printing a `Unit` instance),
  # Rails normally shows every column's current value — which could
  # accidentally leak sensitive data (like encrypted attribute plaintext, if
  # ever decrypted into an in-memory object) into logs/console output/error
  # reports. `[ :id ]` is a one-element Ruby Array containing a single
  # Symbol; setting `attributes_for_inspect` to it means only the `id`
  # column is shown when a record is inspected in production, hiding every
  # other attribute's value from casual inspection output.
  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Blank line — purely visual spacing, has no effect on Ruby.

  # A comment explaining the commented-out block below: it demonstrates
  # "DNS rebinding protection" (`config.hosts`), the same security feature
  # explained in detail in config/environments/development.rb's own
  # `config.hosts` section — restricting which HTTP "Host" header values
  # this app will accept requests for. It stays inactive here (every line
  # in this block starts with `#`), meaning production currently accepts
  # requests for ANY Host header value — see this pass's final "flagged
  # issues" note, since leaving this off is a real (if common/default)
  # security tradeoff worth knowing about explicitly.
  # Enable DNS rebinding protection and other `Host` header attacks.
  # If uncommented, `config.hosts` would be set to a Ruby Array containing:
  # a plain String, `"example.com"` (an exact allowed hostname), and a
  # Regexp, `/.*\.example\.com/` (matching any subdomain of example.com —
  # same Regexp mechanics as explained in development.rb's config.hosts
  # section).
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # A comment (still inside the inactive block above) explaining the final
  # commented-out line below: it would carve out an exception to Host-header
  # checking specifically for the "/up" health-check path, using the same
  # lambda-based `exclude:` mechanism shown in the `config.ssl_options`
  # example further up this file.
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
# `end` closes the `Rails.application.configure do` block opened near the
# top of the file — every setting above only applies while running in the
# production environment.
