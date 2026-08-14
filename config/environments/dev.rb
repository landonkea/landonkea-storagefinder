# config/environments/dev.rb, StorageFinder's FOURTH environment: "dev".
#
# Rails loads exactly one file from config/environments/ at boot, chosen by
# the RAILS_ENV variable. Set RAILS_ENV=dev and this file runs; nothing else
# needs to be told about it.
#
# What "dev" is for here: this is NOT the same thing as running the app on
# your own laptop via ./start.sh (that's plain "development", config/
# environments/development.rb, unaffected by this file). "dev" is a
# deployed, Kamal-managed tier, a disposable preview container for trying
# out a branch before it's worth promoting to staging. Think of it as the
# first rung of a ladder: dev -> staging -> production. Bugs are expected
# and cheap here; nobody's alerting rules or real crawl history live in it.
#
# Why this duplicates production.rb's settings instead of requiring it:
# config/environments/staging.rb already made this same call and explains
# it well, so the short version: Rails environment files are unconditional
# `Rails.application.configure` blocks, requiring another one in from here
# would work today but would silently break if production.rb ever added
# code that assumed RAILS_ENV == "production" specifically. A plain copy
# keeps dev free to diverge later without that being an invisible surprise.
#
# What actually keeps dev safe to run alongside staging and production on
# the same LAN box: config/database.yml has a "dev:" block pointing at its
# own storage/dev*.sqlite3 files, and config/deploy.dev.yml (a separate
# Kamal destination file) gives it its own image, container, and Docker
# volume. Same isolation strategy staging uses, just one tier further out.
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Same posture as production/staging: no reloading, eager load everything
  # at boot. A preview container should behave like the real thing, not
  # like a laptop dev server, the whole point is catching problems before
  # staging does.
  config.enable_reloading = false
  config.eager_load = true

  # Generic error pages for real visitors, not Rails' debug page.
  config.consider_all_requests_local = false

  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.active_storage.service = :local

  # Logs to STDOUT so `bin/kamal logs -d dev` can read them, same as
  # staging/production.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  # In-memory cache, same reasoning as production: this is a single process
  # on a single machine, nothing to coordinate a shared cache with.
  config.cache_store = :memory_store

  # Solid Queue, matching production/staging, see config/environments/
  # production.rb's own comment for why. Known gap, carried over from
  # staging rather than newly introduced here: config/queue.yml and
  # config/recurring.yml only define explicit "production:" sections (no
  # "staging:" or "dev:" keys), and config/cable.yml has the same gap for
  # Action Cable's adapter (adapter falls back to Action Cable's own
  # default, which needs the redis gem this app doesn't have, so a real
  # WebSocket connection or broadcast would error). Already documented,
  # not something skipped here: config/database.yml's "staging: cable:"
  # block comment spells out the cable.yml gap, and the "queue:" block
  # comment above it covers the Solid Queue side. dev inherits the
  # identical situation rather than a new one. Worth a real look before
  # the scheduled-crawl feature (or the crawl-progress WebSocket) is
  # actually exercised on dev or staging, see BUILD_LOG.md's "Known gaps"
  # section.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.default_url_options = { host: ENV.fetch("MAILER_HOST", "storagefinder-dev.local") }

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
