# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!
# (Kept as-is — Rails' own generated explanation of what this file is for.
# Background for a novice: Rails apps run in one of several "environments"
# at a time — development (what you use while coding locally), test (used
# only while running automated tests), and production (the real, live
# version users actually use). Each environment gets its own settings file
# here in config/environments/, because you often want very different
# behavior — e.g. real emails should never send while running tests. Which
# environment is active is controlled by the RAILS_ENV environment
# variable; Rails' own test runner sets it to "test" automatically.)

# `Rails.application.configure do ... end` opens a block where `config` (a
# special object holding every setting for the whole app) can be modified.
# Rails runs this block automatically, but ONLY when the app is booted with
# RAILS_ENV=test — this whole file is skipped otherwise. Anything set on
# `config` here overrides whatever config/application.rb set for the same
# option, but only while running in the test environment.
Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # `config.enable_reloading = false` turns OFF Rails' code-reloading
  # system (which in development, re-reads changed .rb files on every
  # request without restarting the server). Test runs load the app once
  # and run every test against that single loaded copy, so reloading mid-
  # run would be pointless overhead.
  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # `config.active_job.queue_adapter = :test` tells ActiveJob (Rails'
  # background-job framework) to use its special :test adapter, which
  # doesn't actually run jobs — the block comment above explains it records
  # them in memory instead, so test assertions like
  # `assert_enqueued_with`/`perform_enqueued_jobs` (used to check "was a
  # job scheduled?" or "run the scheduled jobs now, inside the test") work
  # predictably. `:test` here is a Ruby Symbol, the standard way Rails
  # config settings pick one option from a fixed set of named choices.
  # The :test adapter records enqueued jobs in-memory instead of actually
  # running them, so assert_enqueued_with/perform_enqueued_jobs work. This is
  # standard Rails test-environment practice and separate from the dev/prod
  # :async choice in config/application.rb.
  config.active_job.queue_adapter = :test

  # `config.eager_load = ENV["CI"].present?` decides whether to eager-load
  # (load every single app file up front at boot, rather than lazily as
  # needed) based on whether a CI environment variable is set at all.
  # `ENV["CI"]` reads that variable (nil if unset); `.present?` is a Rails
  # helper meaning "not nil and not blank" — true only when some CI system
  # (like GitHub Actions) has set that variable, which it conventionally
  # does automatically. So: eager loading is skipped for fast local single-
  # test runs, but turned on automatically when running in CI, to catch
  # loading-related bugs before they reach production.
  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # `config.public_file_server.headers` sets extra HTTP response headers
  # Rails adds when serving static files directly (e.g. images/CSS) out of
  # the public/ folder during tests. `{ "cache-control" => "public,
  # max-age=3600" }` is a Ruby Hash literal (curly braces containing
  # key/value pairs) — here it tells browsers/test HTTP clients they may
  # cache the file for up to 3600 seconds (1 hour), which speeds up test
  # runs that repeatedly fetch the same static assets.
  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # `config.consider_all_requests_local = true` makes Rails show its full,
  # detailed debug error page (with backtrace, local variables, etc.)
  # whenever an unhandled error occurs, instead of a generic error page —
  # useful because test failures should show maximum detail.
  # Show full error reports.
  config.consider_all_requests_local = true
  # `config.cache_store = :null_store` disables caching entirely (the
  # `:null_store` adapter accepts writes but never actually stores or
  # returns anything) — ensures tests never see stale cached data from a
  # previous test accidentally leaking into a later one.
  config.cache_store = :null_store

  # `config.action_dispatch.show_exceptions = :rescuable` controls how
  # unhandled exceptions during a request are displayed. `:rescuable`
  # (a Symbol, one of a few valid choices Rails defines for this setting)
  # means: render the normal error page for exceptions your app declares it
  # can rescue/handle, but let genuinely unexpected exceptions propagate up
  # and fail the test loudly, rather than being silently converted to a
  # generic 500 error page.
  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # `config.action_controller.allow_forgery_protection = false` turns off
  # Rails' CSRF (Cross-Site Request Forgery) protection — the mechanism
  # that normally rejects form submissions missing a valid security token,
  # to stop malicious other-site forms from submitting on a user's behalf.
  # It's disabled in tests because tests routinely submit forms
  # programmatically without going through a real browser page render
  # (which is what normally embeds that token), and there's no real
  # attacker to defend against in a test run.
  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # `config.active_storage.service = :test` tells Active Storage (Rails'
  # file-upload framework) to use the storage service configuration named
  # "test" from config/storage.yml — typically a temporary local directory
  # that can be freely wiped between test runs, keeping uploaded test
  # fixture files out of your real development uploads.
  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # `config.action_mailer.delivery_method = :test` tells Action Mailer
  # (Rails' email-sending framework) to use its :test delivery method,
  # which — as the comment below explains — never contacts a real mail
  # server; it just appends each attempted email to an in-memory array so
  # tests can assert on what WOULD have been sent.
  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # `config.action_mailer.default_url_options = { host: "example.com" }`
  # sets the hostname Action Mailer uses when generating full URLs inside
  # email bodies (e.g. a link back to the app) — mailers can't infer a host
  # from an incoming web request the way controllers can, since sending an
  # email isn't triggered by a browser visiting a URL, so this has to be
  # configured explicitly. "example.com" is a placeholder-safe domain
  # (reserved by IANA for documentation) since tests never actually deliver
  # anything real.
  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # `config.active_support.deprecation = :stderr` tells Rails to print
  # deprecation warnings (notices that some API you're using will be
  # removed in a future Rails version) directly to stderr (the standard
  # error output stream) during test runs, so they're visible in test
  # output/CI logs rather than buried in a log file.
  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # This line is commented out (starts with `#`, so it's inert
  # documentation, not active code) — if uncommented, it would make Rails
  # raise an error whenever an I18n (internationalization/translation)
  # lookup can't find a translation, instead of silently rendering a
  # "translation missing" placeholder string.
  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Also commented out: if enabled, this would annotate every rendered
  # view's HTML output with an HTML comment naming which template file
  # produced it — handy for debugging which partial rendered what, left
  # off by default in tests to keep rendered output exactly matching what
  # tests expect to assert against.
  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # `config.action_controller.raise_on_missing_callback_actions = true`
  # makes Rails raise an error if a controller's `before_action`/
  # `after_action` callback specifies `only:`/`except:` options that name
  # an action which doesn't actually exist on that controller — catching a
  # typo (e.g. referencing a renamed or deleted action) as a loud failure
  # instead of the callback silently never running.
  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Blank line separating the standard Rails-generated settings above from
  # this app's own custom addition below, which has its own explanatory
  # comment.

  # Setting#value uses `encrypts` (see app/models/setting.rb). Fixtures insert
  # rows via raw SQL, bypassing that — this tells Rails to encrypt fixture
  # values for encrypted attributes at load time so test/fixtures/settings.yml
  # can just list plaintext values like everything else.
  # (Comment above is original/pre-existing and already explains the WHY.
  # Mechanically: `encrypts` is Rails' Active Record attribute encryption
  # feature — it transparently encrypts a column's value before saving and
  # decrypts it when read, when going through normal Active Record
  # methods. Test "fixtures" (test/fixtures/*.yml files) are loaded by
  # inserting rows directly into the test database via raw SQL for speed,
  # which skips that automatic encryption — so without this setting, a
  # fixture's plaintext value would end up stored un-encrypted, breaking
  # any code that expects to decrypt it later.)
  config.active_record.encryption.encrypt_fixtures = true
end
# `end` closes the `Rails.application.configure do` block opened at the
# top of the file — every setting above only applies inside the test
# environment.
