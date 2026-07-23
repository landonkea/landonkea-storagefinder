#!/bin/bash
# The "shebang" line. When this file is run directly (e.g. `./start.sh`),
# the operating system reads this very first line to figure out which
# program should interpret the rest of the file — here, `/bin/bash`, the
# Bash shell. Without this line, the OS wouldn't know this is a shell
# script at all and would likely refuse to run it (or misinterpret it).

# `set -e` turns on "exit immediately on error" mode: if ANY command in
# this script fails (returns a non-zero exit status), the whole script
# stops right there instead of continuing on to later commands as if
# nothing went wrong. This is a common safety net in setup/deploy scripts,
# so a failed step (e.g. a missing dependency) doesn't let the script
# barrel ahead and do something nonsensical with a half-broken environment.
set -e

# Figures out the absolute directory this script itself lives in, so the
# rest of the script can `cd` there and run commands relative to the
# project root — regardless of what directory the user happened to be in
# when they ran `./start.sh` (e.g. running it from a different folder via
# a full path, or as a symlink). Working piece by piece from the inside
# out:
#   `${BASH_SOURCE[0]}`  — the path to this very script file, as it was
#                          invoked (may be relative, e.g. "./start.sh").
#   `dirname "..."`      — strips the filename, leaving just the
#                          directory part of that path (still possibly
#                          relative).
#   `cd "..." && pwd`    — changes into that directory, then prints its
#                          FULL absolute path with `pwd` ("print working
#                          directory") — this is what converts a possibly
#                          relative path into a guaranteed absolute one.
#   `$( ... )`           — "command substitution": runs the command inside
#                          the parentheses and substitutes its printed
#                          output as a string, right here.
#   SCRIPT_DIR="..."     — stores that resulting absolute path in a shell
#                          variable named SCRIPT_DIR for later use.
# Note: the `cd` above happens inside a subshell (because it's inside
# `$(...)`), so it does NOT change the CURRENT shell's working directory —
# only the directory used momentarily to compute SCRIPT_DIR.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# NOW actually change the current shell's working directory to the
# project root computed above, so every command below this line (bundle,
# rails, etc.) runs with the project's Gemfile/config files in scope,
# regardless of where the script was originally launched from.
cd "$SCRIPT_DIR"

# Blank line in the script's own logic (not a comment) — `echo ""` prints
# a single empty line to the terminal, purely for visual spacing before
# the banner below, same idea as a blank line in a paragraph of text.
echo ""
# Prints one line of a decorative box-drawing border (built from Unicode
# box-drawing characters like ╔ ═ ╗) as plain text — purely cosmetic, to
# make the startup banner look like a boxed title in the terminal.
echo "╔═══════════════════════════════════════════════════════════╗"
# The middle line of the banner box, containing the actual title text
# "StorageFinder — Starting Up" padded with spaces so the box's left/right
# borders (║) line up visually with the border characters above/below.
echo "║              StorageFinder — Starting Up                  ║"
# The bottom line of the decorative box, closing it off visually.
echo "╚═══════════════════════════════════════════════════════════╝"
# Another blank line for spacing, this time after the banner.
echo ""

# Runs the `ruby` command with the `--version` flag, which prints Ruby's
# installed version info (e.g. "ruby 3.3.0 ...") and captures that
# printed output into the variable `ruby_version`, using the same
# `$(...)` command-substitution technique explained above for SCRIPT_DIR.
ruby_version=$(ruby --version)
# Prints a checkmark plus a friendly "Ruby: <version>" line to the
# terminal so whoever's running this script can visually confirm which
# Ruby version is about to be used, without having to run `ruby --version`
# themselves first. `$ruby_version` inserts the variable's stored value
# into the string (variable interpolation inside double quotes).
echo "✓ Ruby: $ruby_version"
# Same idea as above, but for Bundler (the gem/dependency manager Rails
# apps use) — captures `bundle --version`'s output into a variable.
bundle_version=$(bundle --version)
# Prints Bundler's version, mirroring the Ruby version line above.
echo "✓ Bundler: $bundle_version"
# Blank spacer line.
echo ""
# A plain status message telling the user what's about to happen next —
# purely informational, doesn't affect script behavior.
echo "Checking gems..."
# Runs Bundler's `install` command, which reads the project's Gemfile and
# Gemfile.lock and makes sure every required gem (Ruby library) is
# actually installed, installing any that are missing. `--quiet`
# suppresses Bundler's normal per-gem installation output, so this script
# only shows a concise status instead of a long scrolling gem list.
# Because `set -e` is active above, if this command fails (e.g. a gem
# can't be downloaded/compiled), the whole script stops here.
bundle install --quiet
# Blank spacer line.
echo ""
# Another status message for the next setup step.
echo "Setting up database..."
# Runs Rails' `db:prepare` task, which is a Rails 6+ convenience command
# that does "whatever is needed" to get the database ready for use: it
# creates the database if it doesn't exist yet, loads the schema if the
# database is empty, or runs any pending migrations if the database
# already has some structure — all in one command, safe to run repeatedly.
#   `RAILS_ENV=development` — sets an environment variable for JUST this
#                             one command (it disappears after the command
#                             finishes), telling Rails to use its
#                             "development" environment config/database
#                             rather than production or test.
#   `bundle exec rails ...` — `bundle exec` runs the following command
#                             (`rails db:prepare`) using exactly the gem
#                             versions locked in this project's
#                             Gemfile.lock, rather than whatever Rails
#                             gem might happen to be installed globally.
#   `2>/dev/null`           — redirects file descriptor 2 (standard
#                             error, where warning/error messages are
#                             normally printed) to `/dev/null`, a special
#                             "black hole" device that discards anything
#                             written to it — so any error/warning text
#                             this command prints is hidden from the
#                             terminal.
#   `|| true`               — `||` means "or, if the previous command
#                             failed"; `true` is a command that always
#                             succeeds and does nothing. So even if
#                             `db:prepare` exits with a failure status,
#                             this whole line still reports success
#                             overall, which — combined with `set -e`
#                             above — is what stops a failed database
#                             setup from aborting the rest of this script.
RAILS_ENV=development bundle exec rails db:prepare 2>/dev/null || true
# Blank spacer line before the final "ready" banner.
echo ""
# Top border of the second decorative banner box, marking that startup
# finished and the server is about to launch.
echo "╔═══════════════════════════════════════════════════════════╗"
# Title line of the "ready" banner.
echo "║                  StorageFinder Ready!                     ║"
# A middle divider line (╠ ═ ╣ characters) separating the title from the
# URL lines below it, still part of the same decorative box.
echo "╠═══════════════════════════════════════════════════════════╣"
# Prints the local-machine URL where the app will be reachable once the
# Rails server (started at the bottom of this script) is running.
echo "║  Local:     http://localhost:5555                         ║"
# Prints a second URL — a LAN (Local Area Network) hostname — for
# reaching the same running server from other devices on the same
# network (assuming "storagefinder.local" resolves via mDNS/Bonjour or
# similar local-network name resolution, which is separate from anything
# this script itself sets up).
echo "║  LAN:       http://storagefinder.local                    ║"
# Bottom border closing the decorative box.
echo "╚═══════════════════════════════════════════════════════════╝"
# Blank spacer line.
echo ""
# A plain instruction telling the user how to stop the server once it's
# running (Ctrl+C sends an interrupt signal that stops the foreground
# process — in this case, the Rails server started on the next line).
echo "Press Ctrl+C to stop."
# Blank spacer line before the server actually starts.
echo ""
# Finally, starts the actual Rails web server in the foreground (this
# command does not return/finish until the server is stopped, e.g. by
# Ctrl+C) — this is the last thing the script does.
#   `RAILS_ENV=development` — same per-command environment variable
#                             technique as the db:prepare line above,
#                             ensuring the server boots using development
#                             configuration.
#   `bundle exec rails server` — runs Rails' built-in web server (Puma,
#                             by default in a modern Rails app) using this
#                             project's locked gem versions.
#   `--binding 0.0.0.0`     — tells the server to listen for connections
#                             on ALL of the machine's network interfaces
#                             (not just "localhost"/127.0.0.1), which is
#                             what makes the "LAN" URL printed above
#                             actually reachable from other devices on the
#                             network, instead of only from this machine.
#   `--port 5555`           — tells the server to listen on port 5555,
#                             matching the port number shown in the
#                             "Local"/"LAN" URLs printed in the banner
#                             above.
RAILS_ENV=development bundle exec rails server --binding 0.0.0.0 --port 5555
