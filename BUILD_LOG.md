# BUILD_LOG

How StorageFinder went from nothing to what's in this repo, and how to get
back to a working copy if all you have is this git history.

## What this is

StorageFinder is a self-hosted Rails 8 app for one user: it crawls a
handful of self-storage company sites (Public Storage, U-Haul, Extra
Space, CubeSmart, SmartStop, Devon Self Storage, iStorage/NSA,
StorAmerica) for unit pricing near an address, keeps a price history in
SQLite, and can email or Discord you when something drops below a
threshold. Crawling happens via a headless Chromium browser driven by
Playwright, not an API, since none of these companies expose one.

## Timeline

Everything below comes straight from `git log`, in the order it actually
happened.

**July 22, 2026, initial commit (`6fb8b09`).** The app landed in one
shot, already past a first hardening pass: per-company and total-crawl
timeouts on `CrawlJob` so one stuck site can't hang everything, encrypted-
at-rest `Setting#value` (SMTP passwords, webhook URLs), HTTP Basic Auth
gating the whole app, timeouts on the Discord/SMTP/Playwright shell-outs,
and a fix for a `good_job` dependency that had been referenced but never
actually installed.

**July 23, the comment pass (`3a8a38f`, PR #3).** Every file got
line-by-line explanatory comments added, config files especially (this is
why `config/deploy.yml`, `config/database.yml`, and the environment files
read the way they do, closer to an annotated textbook than typical Rails
boilerplate). Two CI fixes followed same-day (`ca802f7`, `49e112a`,
missing system lib for the `dnssd` gem's build step, missing
`tailwindcss-rails` for asset compilation in test), then a bug-fix pass
(`3c39faf`, PR #4) catching issues the comment pass surfaced along the
way. `99d6130` (PR #5) documented that Extra Space's site blocks scraping
with a CAPTCHA, a company that's still effectively unscrapable today.

**July 25, `7e61cb3`.** Regenerated `config/credentials.yml.enc` and
added `config/credentials/test.yml.enc` + `test.key`, Rails' per-
environment credentials split, so the test suite has its own (non-
sensitive, deliberately committed) encryption keys separate from
production's.

**August 1, `35db1ef`.** Added the staging environment: `config/
environments/staging.rb`, `config/deploy.staging.yml`, and the `staging:`
block in `config/database.yml`, all built to mirror production exactly so
a staging deploy rehearses the real thing rather than testing something
different. Same commit did a cleanup sweep on things flagged earlier and
split `CrawlJob` into smaller pieces. `d0cabf0` added `secret_key_base`
to credentials the same day.

**August 2, the busiest single day.** Six commits: Solid Queue wired up
for scheduled/recurring crawls (`54d7b8e`), ActionCable connections
brought under the same Basic Auth gate as everything else (`81a8e7c`),
bulk-delete for alert rules (`4c51281`), warning/error counts on the
crawl history table (`b759ee0`), StorAmerica's checkbox disabled and
labeled unsupported after its scraper turned out unreliable (`cfe4aef`),
and configurable price-badge color thresholds (`9b80226`). `61a508b`
added the `bullet` gem for catching N+1 queries in development.

**August 3–4.** Dashboard charts, a Leaflet-based facility map with a
nearest-facilities panel and per-alert-rule cooldowns, a persisted test-
results report (`bin/rails test:report`, see `lib/tasks/test_report.rake`)
plus a `docker-compose.yml` for local dev, and a public-facing search page
that needs no auth (`15962a5`), separate from the authenticated dashboard.

**August 5–7.** Documented Brakeman ignore entries for two links already
guarded by `safe_external_url?`, a playwright-ruby-client dependency bump,
and a new CI workflow (`830db9f`, `dc8a541`) that scans commit messages
and author/committer fields for AI-attribution trailers and fails the
build if it finds one.

**August 8, six PRs merged into main in quick succession** (#11 through
#17): the scheduler/charts/auth work, the dashboard charts, the facility
map, the test-report/docker-compose work, the public search page, and a
dependency bump, all landing the same day. `ee12e90` added design-workflow
docs.

**August 9–12.** An em-dash cleanup pass across markdown and source
(`a1c3da1`), a fix for crawl timeout handling, error visibility, and
partial-results display (`72161c2`), and a fix so the AI-attribution
check stops flagging its own commits and ordinary GitHub merge commits
(`4c3dc8d`, the current tip of `main`).

**In progress, not yet on `main`:** a Kamal `dev` environment, one rung
below staging, config-only for now (see "Known gaps" below).

## Rebuilding from scratch

If all you have is this repository (or its git history) and a target
machine, here's what actually gets you to a running, tested app, with
nothing that requires a human to make a judgment call along the way.

**1. Clone and check the toolchain.**

```bash
git clone <this repo> storagefinder && cd storagefinder
cat .ruby-version   # 3.4.9, install via rbenv/rvm/asdf if it's not already present
```

**2. Generate a master key and credentials.** `config/credentials.yml.enc`
is committed (it's encrypted), but `config/master.key` is gitignored on
purpose and was never in git, there's no way to recover the *original*
key from history, and there shouldn't be. A fresh app needs a fresh one:

```bash
bin/rails credentials:edit
```

This is the one step that isn't purely mechanical, `credentials:edit`
opens an editor, because the values that go in (the HTTP Basic Auth
username/password gating the whole app, `secret_key_base`, optionally
SMTP settings) are meant to be chosen, not copied from a prior run. To
run it with zero interactive input instead, set `EDITOR` to a script that
writes the required keys non-interactively, for example:

```bash
cat > /tmp/seed_credentials.rb <<'RUBY'
require "securerandom"
File.write(ARGV[0], {
  secret_key_base: SecureRandom.hex(64),
  auth: { username: "admin", password: SecureRandom.hex(16) }
}.to_yaml)
RUBY
EDITOR="ruby /tmp/seed_credentials.rb" bin/rails credentials:edit
```

Running `bin/rails credentials:edit` for the first time with no existing
`config/master.key` generates both the key and the encrypted file in one
step, no separate `credentials:init` needed.

**3. Run `bin/setup`.** This one script does everything from here:
detects the OS (macOS/Linux/WSL), installs system dependencies (SQLite,
the `libavahi-compat-libdnssd-dev` header the `dnssd` gem's native
extension needs, build tools), runs `bundle install`, prepares the
database (`bundle exec rails db:prepare`, seeds `Setting` rows), installs
Playwright and downloads a Chromium binary for it, and finishes with a
`./start.sh` pointer. It's idempotent, safe to re-run if a step fails
partway and you fix the underlying cause.

```bash
bash bin/setup
```

**4. Verify with the real test suite**, the same command CI runs:

```bash
RAILS_MASTER_KEY=$(cat config/master.key) bin/rails test
```

(`config/credentials/test.key` already ships in the repo for the test
environment specifically, so `bin/rails test` on its own works without
needing the master key at all, the `RAILS_MASTER_KEY` env var above is
only there because some rake tasks and `bin/rails runner` calls decrypt
`config/credentials.yml.enc`, the main one, even outside the test
environment.)

**5. Start it.**

```bash
./start.sh   # http://localhost:5555, also http://storagefinder.local via mDNS
```

**Alternative: build the production Docker image directly**, which sidesteps
`bin/setup` entirely and is arguably the more "zero human input" path
since it's the exact same build Kamal runs:

```bash
docker build -t storagefinder .
docker run -p 3000:80 -e RAILS_MASTER_KEY=$(cat config/master.key) storagefinder
```

The `Dockerfile` handles system deps, `bundle install`, asset
precompilation (using `SECRET_KEY_BASE_DUMMY=1` so it doesn't need real
credentials at build time), and produces a non-root final image that
listens on port 80 internally.

**What you can't fully automate:** an actual Kamal deploy
(`bin/kamal setup`/`deploy`, with or without `-d staging`/`-d dev`) needs
a real server to SSH into. `config/deploy.yml` currently points at
`192.168.0.1`, a placeholder LAN address, no such server exists yet for
this repo. Everything above gets you a running app locally or in a
container; only the deploy step itself needs real infrastructure.

## Known gaps

Found while reviewing the in-progress `dev` environment work (comparing
it against how `staging` is already set up):

- **`config/cable.yml`, `config/queue.yml`, and `config/recurring.yml`
  don't have `staging:` or `dev:` sections**, only `production` (plus
  `development`/`test` for `cable.yml`). This is a real, pre-existing gap
  in `staging`, not something the `dev` work introduced, `config/
  database.yml`'s `staging: cable:` block comment already flags it.
  Practical effect: `cable.yml`'s gap means Action Cable would fall back
  to its own default adapter (needs the `redis` gem, not in this app's
  Gemfile) under `RAILS_ENV=staging` or `RAILS_ENV=dev`, confirmed by
  booting the app under `RAILS_ENV=staging` and calling
  `ActionCable.server.pubsub`, it raises a `Gem::LoadError`. `queue.yml`'s
  gap is harmless (Solid Queue's own hardcoded defaults match what
  `queue.yml` would have set anyway). `recurring.yml`'s gap is more
  serious for staging specifically, since staging's Kamal `job:` role
  (inherited from the base `config/deploy.yml`, not overridden per
  destination) would try to load `recurring.yml`'s `production:` section
  as if it were a single recurring task named "production," which fails
  Solid Queue's own config validation. None of this has been hit yet
  because no server exists to actually run `bin/kamal deploy -d staging`
  against. `dev` sidesteps the `recurring.yml` issue entirely by not
  running a `job:` role at all.
- **StorAmerica's scraper is disabled** in the UI (checkbox present, but
  unchecked and labeled unsupported), see `cfe4aef`.
- **Extra Space can't be scraped at all**, their site serves a CAPTCHA,
  documented in `99d6130`.
- **SMS alerts are stubbed out**, needs a paid Twilio account, see
  `app/services/alerting/alert_delivery_service.rb`.
- **The `dev` Kamal environment is config-only right now**: `config/
  database.yml`'s `dev:` block, `config/deploy.dev.yml`, and `config/
  environments/dev.rb` are all in place and boot-tested locally
  (`RAILS_ENV=dev bin/rails runner` and `RAILS_ENV=dev bin/rails
  db:prepare` both succeed, `bin/kamal config -d dev` renders a valid
  merged config), but nothing has actually been deployed with it, same
  placeholder-server caveat as staging above.
