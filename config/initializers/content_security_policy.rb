# A reminder that, like every file in config/initializers/, this one only
# runs once at application boot — editing it has no effect on a server
# that's already running until you stop and restart the process. (See
# config/initializers/assets.rb for a full explanation of what an
# "initializer" is and why this directory is auto-loaded by Rails.)
# Be sure to restart your server when you modify this file.

# Blank line — purely visual spacing, no effect on Ruby.

# Explains the purpose of the whole block below: a "Content Security
# Policy" (CSP) is an HTTP response header that tells the browser which
# sources (domains/schemes) it's allowed to load scripts, images, styles,
# etc. from for pages served by this app. It's a defense-in-depth measure
# against cross-site scripting (XSS) attacks — even if an attacker manages
# to inject a `<script>` tag into a page, a strict CSP can stop the browser
# from executing it if it doesn't come from an approved source.
# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Blank line — visual spacing before the example code block below.

# --- Everything from here to the end of the file is COMMENTED OUT ---
# Every remaining line in this file starts with a `#`, which means Ruby
# treats the whole thing as plain text/comments, not executable code. None
# of this configuration is actually applied. It's boilerplate left in place
# by Rails' default app generator, showing you the syntax you'd use to turn
# on a CSP if/when you want one. As a result, StorageFinder currently sends
# NO Content-Security-Policy header to browsers at all (see the flagged
# note about this at the end of the annotation pass).

# If active, this line would open a configuration block for the whole
# Rails application: `Rails.application` is the running app instance (see
# assets.rb for what that means); `.configure do ... end` is a Ruby method
# call that takes a block (a chunk of code wrapped in `do...end`) and runs
# it with `config` available inside, letting you set several options at
# once.
# Rails.application.configure do

# If active, this would call `content_security_policy` on `config`,
# passing it a block. The block takes one parameter, named `policy`
# (declared between the pipe characters `|policy|`) — that object is what
# you call methods on below to build up the actual policy rule by rule.
#   config.content_security_policy do |policy|

# If active: sets the "default-src" CSP directive, which is the fallback
# source list used for any resource type (scripts, images, etc.) that
# doesn't have its own more specific directive below. `:self` and `:https`
# are Ruby symbols (lightweight, immutable, named identifiers — written
# with a leading colon — commonly used as fixed keyword-like values instead
# of plain strings). `:self` means "only from this same origin/domain";
# `:https` means "only over an encr8ypted HTTPS connection". Passing both
# as separate arguments means both restrictions apply together.
#     policy.default_src :self, :https

# If active: sets the "font-src" directive specifically for web font files.
# Same `:self, :https` meaning as above, plus `:data`, which additionally
# allows fonts embedded directly in the page as "data:" URIs (base64-
# encoded content inline in the HTML/CSS, rather than a separate network
# request).
#     policy.font_src    :self, :https, :data

# If active: sets the "img-src" directive for images, with the same three
# allowed sources as font-src above (same-origin, HTTPS, and inline
# data: URIs).
#     policy.img_src     :self, :https, :data

# If active: sets the "object-src" directive, which controls plugin-based
# embeds like `<object>`, `<embed>`, and `<applet>` tags (e.g. old Flash
# content). `:none` is a symbol meaning "disallow this entirely from any
# source" — the strictest possible setting, recommended because these tags
# are a common attack vector and rarely needed in modern apps.
#     policy.object_src  :none

# If active: sets the "script-src" directive, restricting where JavaScript
# can be loaded from to same-origin (`:self`) or HTTPS (`:https`) sources
# only — this is the most security-critical directive for preventing XSS,
# since it controls what code the browser is willing to execute.
#     policy.script_src  :self, :https

# If active: sets the "style-src" directive the same way, restricting CSS
# stylesheets to same-origin or HTTPS sources.
#     policy.style_src   :self, :https

# If active, this comment (itself inside the commented-out example) would
# explain the line right below it: a "violation report" is a JSON payload
# the browser POSTs to a URL of your choosing whenever a page tries to
# violate the policy — useful for monitoring/debugging a CSP without
# necessarily blocking anything yet.
#     # Specify URI for violation reports

# If active (and additionally un-commented, since it's double-commented
# out here as an example-within-an-example): would call `policy.report_uri`
# with a path, telling browsers where to send those violation reports.
#     # policy.report_uri "/csp-violation-report-endpoint"

# If active: `end` here would close the `content_security_policy do |policy|`
# block opened several lines above.
#   end

# Blank comment line (just a lone `#` with nothing after it) — inside the
# real (uncommented) version of this code, this would be a blank line for
# visual spacing between the policy block and the nonce settings below.
#

# If active, this comment would explain the "nonce" line right below it: a
# "nonce" (number used once) is a random, per-request token that lets
# specific inline `<script>`/`<style>` tags bypass the strict CSP rules
# above — the browser only trusts an inline script if it carries the exact
# nonce value that request generated, making it useless for an attacker to
# guess.
#   # Generate session nonces for permitted importmap, inline scripts, and inline styles.

# If active: sets `content_security_policy_nonce_generator` to a Ruby lambda
# (an anonymous, callable block of code — `->(request) { ... }` is shorthand
# "stabby lambda" syntax where `request` is the lambda's one parameter and
# the code inside `{ }` is its body). Rails would call this lambda on every
# request needing a nonce; here it returns `request.session.id.to_s` — the
# current visitor's session ID, converted to a String with `.to_s` — reused
# as the nonce value for that request.
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }

# If active: sets which CSP directives the nonce should be attached to.
# `%w(script-src style-src)` is Ruby's "word array" literal shorthand — it
# builds the Array `["script-src", "style-src"]` without needing quotes or
# commas around each word, splitting on whitespace instead.
#   config.content_security_policy_nonce_directives = %w(script-src style-src)

# Blank comment line — visual spacing in the example, same as above.
#

# If active, explains the setting right below: normally you'd have to
# manually pass the nonce to Rails' script/style helper methods yourself;
# turning this boolean on makes Rails add it automatically wherever
# applicable.
#   # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
#   # if the corresponding directives are specified in `content_security_policy_nonce_directives`.

# If active (and additionally un-commented, since it's nested inside the
# already-commented example): would set this boolean config flag to `true`,
# turning on the automatic-nonce-injection behavior described just above.
#   # config.content_security_policy_nonce_auto = true

# Blank comment line — visual spacing.
#

# If active, explains the setting right below: "report-only" mode means the
# browser will still send violation reports (if `report_uri` is configured)
# but will NOT actually block/enforce anything — useful for testing a new
# policy's impact before turning on real enforcement.
#   # Report violations without enforcing the policy.

# If active (and additionally un-commented): would set this boolean flag to
# `true`, switching the whole policy from "enforced" to "observe only" mode.
#   # config.content_security_policy_report_only = true

# If active: this `end` would close the `Rails.application.configure do`
# block opened at the very top of this example.
# end
