# StorageFinder

A self-hosted, single-user tool that crawls self-storage company websites
(Public Storage, U-Haul, Extra Space, CubeSmart, SmartStop, Devon Self
Storage, iStorage/NSA — StorAmerica is a stub awaiting a parser) for unit
pricing near a given address, shows results on a live dashboard, and can
email/Discord you when a price drops or falls below a threshold you set.

It's a Rails 8 app that drives a headless Chromium browser via Playwright to
do the actual scraping, runs crawls as background jobs, and stores results
in SQLite.

## Requirements

- Ruby 3.4.9 (see `.ruby-version`)
- Node.js + npm (for the Playwright CLI/browser)
- SQLite 3

## Local setup

```
bash bin/setup   # installs system deps, gems, sets up the DB, installs Playwright + Chromium
./start.sh       # starts the dev server at http://localhost:5555 (also reachable at http://storagefinder.local)
```

`bin/setup` is safe to re-run. If you'd rather do it by hand: `bundle
install`, then `RAILS_ENV=development bin/rails db:prepare`.

### Authentication

The whole app sits behind HTTP Basic Auth (there's no per-user account
system — it's meant for one person on their own LAN). The username and
password live in Rails credentials:

```
bin/rails credentials:edit
```

look for the `auth:` section. This repo's `config/credentials.yml.enc` is
already set up with an `auth:` block and the `active_record_encryption:`
keys that `Setting#value` needs (SMTP passwords, Discord webhook URLs, etc.
are encrypted at rest, not stored in plaintext) — you just need
`config/master.key` to read/change them. **Basic Auth does not cover the
`/cable` ActionCable endpoint**, since it doesn't route through
`ApplicationController` — live dashboard updates over that socket aren't
gated the same way the rest of the app is.

## Running tests

```
bin/rails db:test:prepare
bin/rails test
```

The suite (`test/`) is plain Minitest — models, controllers, jobs, and the
network-independent parts of the scraping services. It doesn't launch a real
Playwright browser or hit real company websites; those code paths are
covered up to the point where a browser would actually be needed.

## Deployment (Kamal)

This app deploys as a Docker container via [Kamal](https://kamal-deploy.org).

1. Edit `config/deploy.yml`: set `servers.web` to your actual server IP(s)
   and `registry.server`/credentials to wherever you're pushing images.
2. Make sure `config/master.key` exists locally — `.kamal/secrets` reads
   `RAILS_MASTER_KEY` from it (`RAILS_MASTER_KEY=$(cat config/master.key)`).
   **Never commit `config/master.key`** (it's gitignored already).
3. `bin/kamal setup` the first time, `bin/kamal deploy` after that.

Data (SQLite database, Active Storage files) persists across deploys via the
`storagefinder_storage` volume declared in `config/deploy.yml`.

### CI

`.github/workflows/ci.yml` runs Brakeman, bundler-audit, an importmap audit,
RuboCop, and the test suite on every PR and push to `main`. The test job
needs a `RAILS_MASTER_KEY` repository secret (Settings → Secrets and
variables → Actions) set to the contents of `config/master.key` — without
it, the app can't decrypt credentials at boot and the job fails.

## Known limitations

- SMS alerts are stubbed out (needs a paid Twilio account) — see
  `app/services/alerting/alert_delivery_service.rb` for what's needed to
  enable it.
- `history_keep_months` in Settings controls how much crawl history/price
  data is kept; older records are purged automatically after each crawl.
- This is built for one trusted user on a LAN, not multi-tenant or
  public-internet use.
