# This file defines what "Continuous Integration" (CI) means for this app —
# the automated checklist that should run (locally or on a server) before
# code is trusted to merge/deploy. It's NOT loaded automatically when Rails
# boots — it's only read when you deliberately run `bin/ci` (see comment
# below), which is a small executable script (not shown here) that requires
# this file and lets it drive the checks.
# Run using bin/ci

# `CI` here is a class/module provided by Rails' own "CI helper" tooling
# (added by default to new Rails 8 apps). `.run` is a method on it that
# takes a Ruby "block" — the `do ... end` — and runs it, giving you a small
# DSL (Domain Specific Language: custom method calls that read like plain
# instructions, e.g. `step` and `failure` below) for declaring CI steps in
# order. If any step fails, `CI.run` is responsible for stopping/reporting.
CI.run do
  # `step` runs one command as part of the CI pipeline. The first argument
  # is a human-readable label shown in output; the second is the actual
  # shell command to execute. This step re-runs the app's own setup script
  # (bin/setup) but skips starting a local server afterward, since CI just
  # needs the app dependencies/database ready, not a running server.
  step "Setup", "bin/setup --skip-server"

  # Blank line: purely visual separation between setup and the style-check
  # step below — has no effect on behavior.

  # Runs RuboCop (a Ruby static-analysis/style linter) to check that all
  # Ruby code in the app follows the project's configured style rules.
  step "Style: Ruby", "bin/rubocop"

  # Blank line: visual separation before the group of security-related
  # checks below.

  # Runs bundler-audit, which checks every gem in Gemfile.lock against a
  # database of known security vulnerabilities (CVEs) and warns/fails if
  # any installed gem version is unsafe.
  step "Security: Gem audit", "bin/bundler-audit"
  # Runs the importmap gem's own audit command, which checks the JavaScript
  # packages pinned in config/importmap.rb (see that file) against a
  # vulnerability database, the JS equivalent of the gem audit above.
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  # Runs Brakeman, a static-analysis security scanner built specifically for
  # Rails apps (it looks for things like SQL injection, mass assignment,
  # and XSS risks by examining the code, without running it).
  # `--quiet` suppresses Brakeman's normal progress/banner output.
  # `--no-pager` stops it from piping output through a pager like `less`
  # (which would hang non-interactively in CI).
  # `--exit-on-warn` makes Brakeman return a failing exit code if it finds
  # ANY warning, not just high-confidence ones.
  # `--exit-on-error` makes it also fail (with a distinct exit code) if
  # Brakeman itself errors out while scanning, rather than silently passing.
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  # Two blank lines here: visual separation before the optional/commented-out
  # section below. Has no effect on behavior — just spacing in the source.


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # (The comments above and the code below are commented OUT with `#`,
  # meaning none of it currently runs — it's left here as an example/
  # template for a team that wants to wire this up. Every line below is a
  # Ruby comment, not executable code, until someone removes the `#`.)
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
  # `success?` (if uncommented) would be a method provided by the CI DSL
  # that reports whether every `step` run so far has passed. If true, it
  # would run `gh signoff` (via the `step` helper) to mark the GitHub
  # commit status green, unblocking a pull request from merging. If false,
  # `failure` (another DSL method, distinct from `step`) would report a
  # named failure message instead of running a command.
end
# `end` closes the `CI.run do ... end` block that started at the top of the
# file — everything above between `do` and this `end` is the block passed
# to `CI.run`.
