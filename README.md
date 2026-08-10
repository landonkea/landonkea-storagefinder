# StorageFinder

A self-hosted, single-user tool that crawls self-storage company websites
(Public Storage, U-Haul, Extra Space, CubeSmart, SmartStop, Devon Self
Storage, iStorage/NSA, StorAmerica is a stub awaiting a parser) for unit
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
system, it's meant for one person on their own LAN). The username and
password live in Rails credentials:

```
bin/rails credentials:edit
```

look for the `auth:` section. This repo's `config/credentials.yml.enc` is
already set up with an `auth:` block and the `active_record_encryption:`
keys that `Setting#value` needs (SMTP passwords, Discord webhook URLs, etc.
are encrypted at rest, not stored in plaintext) you just need
`config/master.key` to read/change them. HTTP Basic Auth technically only
covers ordinary HTTP requests (it wouldn't automatically protect the
`/cable` ActionCable/WebSocket endpoint, since that connects directly to
`app/channels/application_cable/connection.rb` instead of routing through
`ApplicationController`) that connection class re-checks the same
username/password itself, so `/cable` is gated too.

## Running tests

```
bin/rails db:test:prepare
bin/rails test
```

The suite (`test/`) is plain Minitest, models, controllers, jobs, and the
network-independent parts of the scraping services. It doesn't launch a real
Playwright browser or hit real company websites; those code paths are
covered up to the point where a browser would actually be needed.

### Test results report

```
bin/rails test:report
```

Runs `bin/rails test` and `bin/rubocop`, then writes a single markdown
summary, pass/fail counts, a timestamp, any failures/errors, and the
RuboCop offense count, to `test-results/latest.md`. The report's content
is gitignored (regenerated on demand, not source), but the `test-results/`
directory itself is tracked so the path always exists. The task exits
non-zero if either the test suite or RuboCop found problems, so it can gate
scripts the same way running each tool separately would. CI runs this task
on every push/PR and uploads `test-results/latest.md` as a downloadable
build artifact (see `.github/workflows/ci.yml`) it's additive alongside
the existing lint/test jobs, not a replacement for them.

## Local development with Docker Compose

If you'd rather not install Ruby/SQLite/Node locally, `docker-compose.yml`
lets you run the whole app in a container built from the same `Dockerfile`
Kamal uses for production images:

```
export RAILS_MASTER_KEY=$(cat config/master.key)   # or put this line in a .env file
docker compose up --build
```

The app is then reachable at <http://localhost:3000>. Data (SQLite
databases for the app, Solid Queue, and Solid Cable, plus any Active
Storage uploads) persists across `docker compose down`/`up` cycles in a
named Docker volume mounted at `/rails/storage` inside the container, no
separate database container is needed since this app is entirely
SQLite-based (see `config/database.yml`). `RAILS_MASTER_KEY` must be set
(from `config/master.key`, which is gitignored and never committed) because
booting the app decrypts `config/credentials.yml.enc`, same as in CI and in
a real Kamal deploy.

This runs the same production-mode image Kamal deploys (the `Dockerfile`
bakes in `RAILS_ENV=production`), so it's meant for exercising the fully
packaged app locally, not for hot-reloading development, for that, use
`./start.sh` per the "Local setup" section above.

## Environments

This app has three environments, each with its own settings file under
`config/environments/` and, for the two that get deployed, its own
isolated data:

| Environment  | `RAILS_ENV`  | Where it runs                          | Data files |
|--------------|--------------|-----------------------------------------|------------|
| `development`| `development`| Your own machine, via `./start.sh`      | `storage/development.sqlite3` |
| `staging`    | `staging`    | The same LAN server as production (192.168.0.1), as a separate container | `storage/staging*.sqlite3` |
| `production` | `production` | The LAN server (192.168.0.1), the real deploy | `storage/production*.sqlite3` |

**`staging` exists as a rehearsal environment**, not a second "real" app.
`config/environments/staging.rb` intentionally duplicates
`config/environments/production.rb` line-for-line (see that file's own
top-of-file comment for why it's a duplicate rather than a `require`) so
that deploying to staging exercises exactly the same code paths and Rails
settings a real production deploy would, eager loading, eager error pages,
the works, but against entirely separate data (`config/database.yml`'s
`staging:` block points at `storage/staging*.sqlite3`, never touching
`storage/production*.sqlite3`) and a separate Kamal-managed container
(`config/deploy.staging.yml`, a Kamal "destination" file, see below).

### Deploying staging

```
bin/kamal deploy -d staging
```

This deploys a second, independent container (`storagefinder-staging`,
distinct image name, distinct `storagefinder_staging_storage` Docker
volume) to the *same* physical server as production, there's only one
server available on this LAN setup, so "staging" means "an isolated
container alongside production," not a separate machine. It does **not**
touch the running production container, its volume, or its data.

Staging is reached via its own Host header (`storagefinder-staging.local`)
rather than production's catch-all routing, see the `proxy:` section of
`config/deploy.staging.yml` for the full explanation, including how to
actually hit it (`curl -H "Host: storagefinder-staging.local"
http://192.168.0.1/`, or add a manual DNS/hosts-file entry) since this
app's mDNS initializer only ever announces the plain `storagefinder.local`
name regardless of environment.

**Important:** `bin/kamal deploy -d staging` must be run from the LAN,
i.e. from the repo owner's own machine on the same network as
192.168.0.1, it opens a real SSH connection to that server. It cannot be
run from a sandboxed/cloud environment with no route to the LAN.

Before deploying for real, you can validate the merged staging config
locally without touching the server at all:

```
bin/kamal config -d staging
```

This prints Kamal's fully-merged configuration (base `config/deploy.yml` +
`config/deploy.staging.yml`) and will fail loudly if anything doesn't
validate, a good pre-flight check before ever opening an SSH connection.

## Deployment (Kamal)

This app deploys as a Docker container via [Kamal](https://kamal-deploy.org).

1. Edit `config/deploy.yml`: set `servers.web` to your actual server IP(s)
   and `registry.server`/credentials to wherever you're pushing images.
2. Make sure `config/master.key` exists locally, `.kamal/secrets` reads
   `RAILS_MASTER_KEY` from it (`RAILS_MASTER_KEY=$(cat config/master.key)`).
   **Never commit `config/master.key`** (it's gitignored already).
3. `bin/kamal setup` the first time, `bin/kamal deploy` after that.
4. For a staging rehearsal instead of a real production deploy, add
   `-d staging` to any Kamal command (e.g. `bin/kamal deploy -d staging`),
   see the "Environments" section above.

Data (SQLite database, Active Storage files) persists across deploys via the
`storagefinder_storage` volume declared in `config/deploy.yml` (production)
or the separate `storagefinder_staging_storage` volume declared in
`config/deploy.staging.yml` (staging).

### Background jobs & the scheduler

Production and staging run background jobs through
[Solid Queue](https://github.com/rails/solid_queue) instead of the
in-process `:async` adapter development uses, `config/deploy.yml` deploys
a second container (the `job:` role, running `bin/jobs`) alongside the
normal web container specifically to run it. This is what makes the
Settings page's "Enable scheduled automatic crawls" toggle actually work:
`config/recurring.yml` has Solid Queue run `ScheduledCrawlCheckJob`
(`app/jobs/scheduled_crawl_check_job.rb`) once a minute; it checks
`schedule_enabled`/`schedule_cron`/`schedule_city`/`schedule_radius_miles`
against the current time and, when they match, kicks off a crawl exactly
like clicking "Run Crawl" would. If you deploy with `bin/kamal setup`, both
roles get created automatically; if you're upgrading an existing deploy,
re-run `bin/kamal setup` (not just `deploy`) so the new `job:` role's
container gets created.

### CI

`.github/workflows/ci.yml` runs Brakeman, bundler-audit, an importmap audit,
RuboCop, and the test suite on every PR and push to `main`. The test job
needs a `RAILS_MASTER_KEY` repository secret (Settings → Secrets and
variables → Actions) set to the contents of `config/master.key`, without
it, the app can't decrypt credentials at boot and the job fails.

A separate `test_report` job additionally runs `bin/rails test:report` (see
"Test results report" above) and uploads `test-results/latest.md` as a
downloadable build artifact on every run, pass or fail, it doesn't gate
the workflow itself, since the `lint`/`test` jobs already do that.

## Known limitations

- SMS alerts are stubbed out (needs a paid Twilio account), see
  `app/services/alerting/alert_delivery_service.rb` for what's needed to
  enable it.
- `history_keep_months` in Settings controls how much crawl history/price
  data is kept; older records are purged automatically after each crawl.
- This is built for one trusted user on a LAN, not multi-tenant or
  public-internet use.
