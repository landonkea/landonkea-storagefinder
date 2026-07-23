# WHAT IS THIS FILE?
# Docker is a tool for packaging an application together with everything it
# needs to run (a specific OS, system libraries, the Ruby interpreter, this
# app's gems and code) into a single, portable unit called an "image" — an
# image can then be run as an isolated, reproducible process (a
# "container") on any machine that has Docker installed, regardless of what
# that machine has (or doesn't have) natively installed. A `Dockerfile` is
# the recipe/script Docker reads to BUILD such an image: each instruction
# below (FROM, RUN, COPY, etc.) adds one more layer on top of the previous
# state. This project's deploy tool, Kamal (see the `kamal` gem in the
# Gemfile and config/deploy.yml), builds an image from exactly this file
# and ships it to the configured server(s).

# `# syntax=docker/dockerfile:1` is a special "parser directive" comment —
# even though it starts with `#` like an ordinary comment, Docker's build
# engine specifically recognizes this exact pattern (it must be the very
# first line) and reads it BEFORE building anything, to pick which version
# of the Dockerfile instruction syntax to use. `docker/dockerfile:1` means
# "always use the latest compatible 1.x syntax," picking up small
# improvements automatically.
# syntax=docker/dockerfile:1
# `# check=error=true` is another special directive comment: it turns on
# Docker's built-in Dockerfile linter and tells it to treat any lint
# warning as a hard build-time ERROR (failing the build) instead of merely
# printing a warning and continuing.
# check=error=true

# Blank line — pure visual separation; has no effect on the build.

# Plain-English usage notes (pre-existing comments, ignored by Docker
# itself) explaining that this Dockerfile targets PRODUCTION use, and
# giving the exact commands for building and running the image by hand
# (as an alternative to using Kamal, which does this automatically).
# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t storagefinder .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name storagefinder storagefinder

# Blank line — pure visual separation.

# Another plain-English note pointing to Rails' own docs for setting up a
# separate, development-oriented containerized environment, since (per the
# note above) this particular Dockerfile is not meant for that purpose.
# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Blank line — pure visual separation.

# Reminder comment for whoever edits this file: the RUBY_VERSION value set
# below should be kept matching the version pinned in .ruby-version (a file
# this comment pass intentionally does not touch), so the Docker image and
# local development both run the exact same Ruby.
# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
# `ARG RUBY_VERSION=3.4.9` declares a build-time variable (an "ARG," as
# opposed to an "ENV" further down, which is different — ARGs exist only
# during the build and aren't kept in the final running container).
# `=3.4.9` supplies its default value, usable immediately below via
# `$RUBY_VERSION`; anyone building this image could also override it, e.g.
# `docker build --build-arg RUBY_VERSION=3.4.10 ...`.
ARG RUBY_VERSION=3.4.9
# `FROM ... AS base` is the instruction that starts a new build stage: it
# picks a starting image to build on top of, instead of starting from
# nothing. `docker.io/library/ruby:$RUBY_VERSION-slim` names an official
# published Ruby image — `docker.io/library/` is Docker Hub's namespace for
# official images, `ruby` is the image name, and the tag
# `$RUBY_VERSION-slim` (substituting the ARG declared just above) selects a
# specific Ruby version built on a "slim" (stripped-down, smaller) Debian
# Linux base. `AS base` labels this particular stage with the name "base"
# so later stages in this same file can refer back to it — this Dockerfile
# uses Docker's "multi-stage build" feature, building more than one stage
# and discarding some of the intermediate work from the final image (see
# the "build" and final stages below).
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Blank line — pure visual separation.

# Comment explaining the instruction below: this sets which directory,
# INSIDE the image/container, is considered "home" for this app's files.
# Rails app lives here
# `WORKDIR /rails` both creates the /rails directory inside the image (if
# it doesn't already exist) and sets it as the "current directory" for
# every subsequent instruction in this Dockerfile (COPY destinations, RUN
# commands, etc. are all relative to here from this point forward, unless
# given an absolute path).
WORKDIR /rails

# Blank line — pure visual separation.

# Comment describing the RUN instruction below: it installs OS-level
# packages needed at RUNTIME (as opposed to only during the build).
# Install base packages
# `RUN` executes a shell command WHILE BUILDING the image, and bakes
# whatever that command changed on disk into the image as a new layer. The
# trailing `&& \` at the end of each sub-line here chains multiple shell
# commands together into ONE single RUN instruction/layer (Docker best
# practice — each separate RUN adds a layer, so combining related steps
# into one keeps the image smaller and the cleanup step below actually
# effective). `\` at the very end of a line is shell line-continuation
# syntax: it tells the shell "this command isn't finished, keep reading the
# next line as if it were on this same line."
# IMPORTANT SYNTAX NOTE, verified by hand: a `#` comment can NOT be
# inserted BETWEEN the individual `\`-continued lines of a shell command —
# doing so breaks the line continuation and corrupts the command (each
# "continued" line would instead be parsed as its own separate, unrelated
# command). So the three steps chained below are all explained together
# here, up front, instead of one comment per continuation line:
#   1. `apt-get install --no-install-recommends -y curl libjemalloc2
#      libvips sqlite3` installs specific Debian packages this app needs at
#      runtime: curl (used by the docker-entrypoint/healthchecks),
#      libjemalloc2 (a faster memory allocator, wired in via LD_PRELOAD
#      below), libvips (an image-processing library, likely used via
#      Ruby's image-handling gems), and sqlite3 (the database engine
#      itself, matching the `sqlite3` gem in the Gemfile).
#      `--no-install-recommends` skips optional "recommended" packages
#      Debian would otherwise pull in by default, keeping the image
#      smaller. `-y` auto-confirms the install prompt (no interactive
#      terminal exists during a Docker build).
#   2. `ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2
#      /usr/local/lib/libjemalloc.so` creates a symbolic link (a filesystem
#      shortcut/alias) so a fixed, predictable path
#      (/usr/local/lib/libjemalloc.so) always points at the actual
#      jemalloc library file, whose real path varies by CPU architecture.
#      `$(uname -m)` is shell command substitution: it runs `uname -m`
#      (prints the machine's hardware architecture, e.g. "x86_64" or
#      "aarch64") and splices that output directly into the surrounding
#      string, so this line works on either architecture without being
#      hardcoded to just one.
#   3. `rm -rf /var/lib/apt/lists /var/cache/apt/archives` deletes the
#      package-manager's downloaded package lists and cached .deb archive
#      files — only needed during installation, not afterward. Removing
#      them within this SAME RUN/layer matters: deleting them in a later,
#      separate RUN would NOT shrink the image, since earlier layers are
#      immutable once created. `-r` means recursive (needed for
#      directories), `-f` means force (don't complain/fail if a path
#      doesn't exist).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Blank line — pure visual separation.

# Comment describing the ENV instruction below.
# Set production environment variables and enable jemalloc for reduced memory usage and latency.
# `ENV` sets one or more environment variables that persist inside the
# built image AND any container run from it (unlike ARG above, which only
# exists during the build). The trailing `\` on each line is the same
# shell-style line-continuation used above, letting this be read as one
# single ENV instruction setting four variables at once.
# Same syntax constraint as the RUN block above applies to ENV's `\`
# continuations too — no comment can sit between two continued lines, so
# all four variables set below are explained together here first:
#   - `RAILS_ENV="production"` tells Rails which environment config to
#     boot under (see config/environments/production.rb).
#   - `BUNDLE_DEPLOYMENT="1"` turns on Bundler's "deployment mode," which
#     requires an exactly-matching Gemfile.lock (no auto-resolving/
#     updating versions at install time) and installs gems into a fixed,
#     predictable location — appropriate safety behavior for production.
#   - `BUNDLE_PATH="/usr/local/bundle"` tells Bundler exactly where, inside
#     the image, to install all gems — a fixed path makes it easy for the
#     multi-stage COPY instructions further down to grab just that folder.
#   - `BUNDLE_WITHOUT="development"` tells Bundler to skip installing any
#     gem listed only under the Gemfile's `group :development` blocks (see
#     the Gemfile) — those tools (like web-console) are dev-only and have
#     no place in a production image.
#   - `LD_PRELOAD="/usr/local/lib/libjemalloc.so"` is a special environment
#     variable the Linux dynamic linker itself understands: it forces every
#     program run in this container to load the given shared library FIRST
#     — here, the jemalloc memory allocator symlinked above — effectively
#     replacing Ruby's/glibc's normal memory allocator with jemalloc
#     project-wide, reducing memory usage and latency for Ruby workloads.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Blank line — pure visual separation.

# Comment explaining the purpose of the NEXT stage: it exists only to do
# work whose intermediate byproducts (compilers, build tool source caches,
# etc.) should NOT end up in the final shipped image.
# Throw-away build stage to reduce size of final image
# `FROM base AS build` starts a SECOND build stage, based on everything
# already built in the "base" stage above (re-using its layers), and
# labels this new stage "build." Nothing from this stage automatically
# ends up in the final image — only instructions explicitly using `COPY
# --from=build` (see the final stage, far below) pull specific files back
# out of it. This is the essence of a Docker "multi-stage build": heavy
# build-only tooling can be installed and used here, then left behind.
FROM base AS build

# Blank line — pure visual separation.

# Comment describing the RUN instruction below: unlike the "base" stage's
# package install (runtime needs), this one installs packages needed only
# to COMPILE things (native gem extensions, etc.) during the build.
# Install packages needed to build gems
# Same overall pattern as the base stage's package install above: update
# the package index, install specific packages, then clean up apt's cache
# — all chained into one RUN/layer with `&&` and line-continuing `\`.
# Same "no comments between `\`-continued lines" constraint as above.
# `apt-get install --no-install-recommends -y build-essential git libvips
# libyaml-dev pkg-config` installs: build-essential (a bundle of core
# compiler tools like gcc and make — needed because some gems include
# native C extensions that must be compiled during `bundle install`), git
# (some gems are installed directly from a git repository rather than
# RubyGems.org, which requires git to clone them), libvips (needed again
# here, at its development/header-file level, so any gem that compiles
# against it can find what it needs), libyaml-dev (development headers for
# YAML parsing, needed to compile Ruby's/Psych's YAML support), and
# pkg-config (a helper tool build scripts use to locate installed
# libraries' compiler flags automatically). The final `rm -rf` is the same
# cleanup rationale as in the base stage above: remove apt's package
# lists/cache within this same layer to avoid bloating the (throwaway, in
# this case) "build" stage image further than needed.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Blank line — pure visual separation.

# Comment describing the section below: copying in just what's needed to
# install this app's Ruby gem dependencies.
# Install application gems
# `COPY vendor/* ./vendor/` copies every file/folder directly inside this
# project's local `vendor/` directory into a `vendor/` directory inside the
# image (relative to the current WORKDIR, /rails, set back in the base
# stage — WORKDIR carries forward into stages built FROM that one). `*` is
# a shell-style wildcard meaning "everything in this folder." Vendored
# code (e.g. a locally-committed copy of a JS library) needs to be present
# before `bundle install` runs below, in case any gem's install process
# expects it.
COPY vendor/* ./vendor/
# `COPY Gemfile Gemfile.lock ./` copies just these two specific files into
# the image's current WORKDIR. Deliberately copying ONLY the Gemfile and
# its lock file here — not the rest of the app's source code yet — is a
# Docker layer-caching optimization: as long as these two files don't
# change between builds, Docker can reuse the cached result of the
# (often slow) `bundle install` below instead of re-running it, even if
# other, unrelated application code changed.
COPY Gemfile Gemfile.lock ./

# Blank line — pure visual separation.

# `RUN bundle install && \` runs Bundler to actually download and install
# every gem listed in the Gemfile/Gemfile.lock just copied in, honoring the
# BUNDLE_* environment variables set back in the base stage (deployment
# mode, install path, skip the development group).
# Same "no comments between `\`-continued lines" constraint as above.
# `rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache
# "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git` deletes several categories of
# files that were useful only DURING installation but take up space
# unnecessarily afterward: Bundler's own local config directory
# (`~/.bundle/`), the downloaded `.gem` package cache (`.../cache`), and,
# for any gems that were installed directly from a git repository, their
# embedded `.git` history folders (which can be surprisingly large and
# serve no purpose once the gem is installed). `"${BUNDLE_PATH}"` re-reads
# the BUNDLE_PATH environment variable set earlier — the `${...}` braces
# are the explicit form of shell variable substitution (equivalent to
# `$BUNDLE_PATH`, just unambiguous when immediately followed by other text
# like `/ruby`). Then, running bootsnap's precompilation step in parallel
# (the default) can hit a real bug when the build itself is running under
# QEMU emulation (e.g. building an ARM image on an x86 machine, or vice
# versa) — the linked GitHub issue tracks it. `-j 1` avoids the bug by
# forcing bootsnap to use just one (1) worker/job instead of several in
# parallel. `bundle exec bootsnap precompile -j 1 --gemfile` runs the
# `bootsnap` gem's precompile command (via `bundle exec`, which ensures the
# exact gem versions from this project's Gemfile.lock are used) with the
# `--gemfile` flag, which specifically precompiles caches for the installed
# GEMS themselves (as opposed to this app's own code, done in a separate
# step below) — speeding up how quickly Ruby can load all these gems'
# files on every future boot of the container.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Blank line — pure visual separation.

# Comment describing the instruction below: now that gems are installed
# (cached in their own layer above), bring in the actual application code.
# Copy application code
# `COPY . .` copies EVERYTHING from the build context (by default, this
# project's whole directory, minus anything excluded via a `.dockerignore`
# file, not covered by this comment pass) into the image's current WORKDIR
# (/rails). This is placed intentionally AFTER the gem-install step above,
# so that any code-only change (which happens far more often than a
# Gemfile change) doesn't invalidate/re-run the slower `bundle install`
# layer — Docker's layer cache is invalidated starting from the first
# instruction whose input actually changed, and reuses every earlier,
# still-valid layer.
COPY . .

# Blank line — pure visual separation.

# Comment describing the RUN instruction below: this precompiles caches
# for this app's OWN code (as opposed to the `--gemfile` step above, which
# only covered installed gems).
# Precompile bootsnap code for faster boot times.
# Repeats the same explanation as above regarding the QEMU parallel-
# compilation bug, since this is a second, separate invocation of the same
# underlying tool with the same `-j 1` safeguard.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
# `RUN bundle exec bootsnap precompile -j 1 app/ lib/` runs bootsnap's
# precompile step again, this time pointed at two specific directories —
# `app/` and `lib/`, this project's own Ruby source code — now that it's
# actually present in the image (copied by the `COPY . .` line just
# above). Precompiling ahead of time means the running container doesn't
# have to pay this cost on its very first boot.
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Blank line — pure visual separation.

# Comment describing the instruction below: builds this app's static
# frontend assets (compiled CSS/JS/etc.) ahead of time, during the image
# build, rather than doing it later at container startup.
# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
# `RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile` runs the
# Rails asset-compilation Rake task (see the Rakefile for how such tasks
# get registered/discovered) via this project's own `bin/rails` binstub.
# Setting `SECRET_KEY_BASE_DUMMY=1` as a one-off environment variable (only
# for this single command, using the `VAR=value command` shell syntax)
# tells Rails it's fine to boot with a placeholder/fake secret key base for
# THIS specific task — asset precompilation doesn't actually need the
# app's real encrypted credentials (config/credentials.yml.enc, protected
# by RAILS_MASTER_KEY), so this avoids requiring that real secret to be
# present/baked into the image just to build CSS/JS bundles.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Three blank lines above (pre-existing spacing) — pure visual separation,
# marking a clear break before the final image stage begins below.

# Comment describing the stage below: this is the stage that actually
# becomes the final, shipped image — everything from the "build" stage
# above is discarded except what's explicitly copied out of it next.
# Final stage for app image
# `FROM base` starts the THIRD (and final) build stage, based again on the
# "base" stage from earlier (NOT on "build" — meaning none of the extra
# build-only packages installed in the "build" stage, like build-essential
# or git, are present here, keeping the final image smaller/more secure).
# No `AS <name>` is given here because nothing later needs to refer back to
# this stage by name — it's simply the last one, and by Docker convention
# the LAST stage in a Dockerfile is the one that becomes the final image.
FROM base

# Blank line — pure visual separation.

# Comment describing the instructions below: creating and switching to a
# non-root Linux user, a security best practice for containers (if an
# attacker ever manages to run code inside the container, they get only
# this limited user's permissions, not full root/administrator access).
# Run and own only the runtime files as a non-root user for security
# `RUN groupadd --system --gid 1000 rails && \` creates a new Linux user
# GROUP named "rails." `--system` marks it as a system group (Linux
# convention for groups meant for services rather than interactive human
# users). `--gid 1000` fixes its numeric group ID to exactly 1000, chosen
# deliberately/predictably (matching the `--uid 1000` chosen for the user
# below and the `1000:1000` used later in USER/COPY --chown) rather than
# letting the system pick an arbitrary next-available ID.
# Same "no comments between `\`-continued lines" constraint as above.
# `useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash`
# creates a new Linux USER named "rails," with numeric user ID 1000
# (`--uid`), belonging to the "rails" group created just above
# (`--gid 1000`), with a home directory automatically created for it
# (`--create-home`), and using `/bin/bash` as its default login shell
# (relevant if anyone ever `docker exec`s into a running container as this
# user and expects an interactive shell to work).
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
# `USER 1000:1000` switches the "current user" for every REMAINING
# instruction in this Dockerfile — and, crucially, for the container's main
# process once it actually runs — from the default root user to this
# numeric user:group pair (1000:1000, matching the rails user/group created
# above). Using the numeric IDs directly here (rather than the name
# "rails") is a common Docker convention that also works correctly even if
# some other tooling inspects the image before the name mapping is
# available.
USER 1000:1000

# Blank line — pure visual separation.

# Comment describing the COPY instructions below: pulling the actual
# useful output (installed gems, application code) OUT of the "build"
# stage from earlier, since this final stage started fresh `FROM base`
# and doesn't have them yet.
# Copy built artifacts: gems, application
# `COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"`
# copies the installed-gems directory from the earlier "build" stage
# (`--from=build`) into the exact same path in THIS stage — re-reading the
# BUNDLE_PATH environment variable (set back in the base stage, so it's
# identical and available in every stage built from it) as both source and
# destination. `--chown=rails:rails` sets the ownership of the copied
# files to the rails user/group created above, as they're copied in (a
# combined copy+chown is more efficient than copying as root then running
# a separate `chown` command afterward, which would create an extra,
# larger image layer).
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
# `COPY --chown=rails:rails --from=build /rails /rails` — same idea, but
# copying this app's actual application code (and any files generated
# during the build, like precompiled assets/bootsnap caches) from the
# "build" stage's /rails directory into this stage's /rails directory,
# again owned by the rails user/group.
COPY --chown=rails:rails --from=build /rails /rails

# Blank line — pure visual separation.

# Comment describing the ENTRYPOINT instruction below.
# Entrypoint prepares the database.
# `ENTRYPOINT [...]` sets the fixed command that always runs first whenever
# a container is started from this image — unlike CMD below (which CAN be
# overridden entirely at `docker run` time), ENTRYPOINT normally stays
# fixed, with anything from CMD/run-time arguments appended onto it as
# extra arguments instead of replacing it outright. The square-bracket
# form `["/rails/bin/docker-entrypoint"]` is Docker's "exec form" syntax —
# it runs the given program directly (as an array of the program path plus
# arguments) rather than wrapping it in a shell first. `docker-entrypoint`
# is this project's own script (see bin/docker-entrypoint), which per the
# comment above handles preparing the database before the real server
# command (from CMD below) actually starts.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Blank line — pure visual separation.

# Comment describing the instructions below: what network port this
# container listens on, and the default command that runs the actual web
# server (as an argument appended after the ENTRYPOINT script above).
# Start server via Thruster by default, this can be overwritten at runtime
# `EXPOSE 80` documents (for humans, and for tools that read image
# metadata) that this container expects to accept network connections on
# port 80 — it does NOT actually publish/open that port on its own; the
# `docker run -p 80:80 ...` example near the top of this file, or Kamal's
# own configuration, is what actually maps a real port to it at run time.
EXPOSE 80
# `CMD ["./bin/thrust", "./bin/rails", "server"]` sets the DEFAULT command
# to run (again in Docker's exec-form array syntax) — passed as arguments
# to the ENTRYPOINT script above, per how ENTRYPOINT+CMD combine. `./bin/
# thrust` is Thruster, a small HTTP proxy/booster placed in front of Puma
# (added via the `thrust` binstub, not a Gemfile gem) that handles things
# like HTTP compression and asset caching; it's told to then run `./bin/
# rails server` (the actual Rails/Puma web server) behind it. Per the
# comment above, someone running this image manually can override this
# entire CMD with a different command at `docker run` time if needed —
# e.g. to run a one-off Rake task inside a container from this same image
# instead of starting the server.
CMD ["./bin/thrust", "./bin/rails", "server"]
