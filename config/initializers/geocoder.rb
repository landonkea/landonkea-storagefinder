# =============================================================================
# GEOCODER CONFIGURATION
# =============================================================================
# Geocoder converts city names and addresses to GPS coordinates.
# We use Nominatim (OpenStreetMap) which is FREE and requires no API key.
#
# Nominatim rate limit: max 1 request per second — we add a small delay
# to respect this. If you need faster geocoding or higher limits,
# you can sign up for a free Google Geocoding API key and switch to :google.
# =============================================================================
# (This box comment was already here and explains the overall purpose of
# the file: it configures the "geocoder" Ruby gem, a third-party library
# this app uses to turn place names typed by users, like "Austin, TX", into
# latitude/longitude coordinates it can use for distance calculations and
# map display. Like every file in config/initializers/, this code runs
# once at application boot — see config/initializers/assets.rb for a full
# explanation of what an "initializer" is.)

# Blank line — purely visual spacing, has no effect on Ruby.

# `Geocoder` is a module/class provided by the geocoder gem (added to this
# app's Gemfile). `.configure` is a class method on it that accepts a Hash
# (a set of key/value settings) and applies it as the gem's global
# configuration. The opening parenthesis `(` here starts the argument list
# passed to `.configure`; because the argument itself is a Hash literal,
# Ruby lets you omit the curly braces `{ }` you'd normally need for a hash
# literal when it's the last/only argument to a method call — the
# `key: value,` pairs below are understood as one big Hash argument.
Geocoder.configure(
  # `lookup:` is one Hash key (Ruby lets you write symbol keys like
  # `:lookup` as `lookup:` when followed by a value, a shorthand called
  # "new hash syntax"). Its value, `:nominatim`, is a Symbol (see
  # filter_parameter_logging.rb for what a Symbol is) that tells the
  # geocoder gem which geocoding backend/service to talk to. Nominatim is
  # OpenStreetMap's free, keyless geocoding service — no sign-up or paid
  # account is needed to use it, unlike most commercial alternatives.
  # Use OpenStreetMap's Nominatim geocoding service — free, no API key
  lookup:  :nominatim,

  # Blank line — visual spacing between settings, no effect on Ruby.

  # `ip_lookup:` configures a SEPARATE feature of the gem: looking up an
  # approximate location from a visitor's IP address (as opposed to
  # `lookup:` above, which geocodes typed-in place names/addresses).
  # `:ipinfo_io` selects the ipinfo.io service as that backend. The comment
  # notes this isn't actually used anywhere in StorageFinder's own code
  # today, but is set anyway so the gem has a sane default if IP lookup
  # ever gets used later.
  # Use IP info for IP address lookups (not used in StorageFinder but good to set)
  ip_lookup: :ipinfo_io,

  # Blank line — visual spacing, no effect on Ruby.

  # Explains why the setting below exists: many public APIs, including
  # Nominatim, require every request to identify the calling application
  # via the standard HTTP "User-Agent" header. Nominatim's usage policy
  # specifically requires a descriptive, non-generic User-Agent — requests
  # without one (or with a generic browser-like one) can be blocked/banned.
  # Nominatim requires a User-Agent identifying your app
  # Without this, requests will be rejected
  # `http_headers:` takes a nested Hash as its value — the `{` below opens
  # that inner Hash literal (this one DOES need explicit braces, because it
  # is not the last/only argument to a method call, just one value inside
  # the outer Hash).
  http_headers: {
    # This Hash has one key/value pair: the STRING key `"User-Agent"`
    # (quoted, not a symbol, because HTTP header names aren't valid Ruby
    # identifiers/symbols — they contain a hyphen) maps via `=>` (Ruby's
    # "hash rocket," the older syntax for hash pairs, still required when
    # the key isn't a bare symbol) to the string value that will literally
    # be sent as this header's content on every geocoding HTTP request.
    "User-Agent" => "StorageFinder/1.0 (self-hosted LAN storage price tracker)"
  },
  # This closing brace `}` ends the `http_headers:` inner Hash literal
  # opened above; the trailing comma after it separates this whole
  # `http_headers: { ... }` entry from the next setting in the outer Hash.

  # Blank line — visual spacing, no effect on Ruby.

  # Explains the setting below: how long (in seconds) the gem will wait for
  # a response from the geocoding service before giving up and raising a
  # timeout error, so a slow/unreachable Nominatim server can't hang the
  # app indefinitely.
  # Timeout for geocoding requests (seconds)
  timeout: 10,

  # Blank line — visual spacing, no effect on Ruby.

  # Explains the two settings below together: `cache:` tells the gem WHERE
  # to store previously-looked-up results (so the exact same place name
  # doesn't need to be re-geocoded every time it's looked up), and
  # `cache_options:` (further below) configures how long those cached
  # results should be kept before being treated as stale.
  # Cache geocoding results in Rails cache to avoid re-geocoding the same city
  # This respects Nominatim's rate limit by not re-requesting recently seen addresses
  # `Rails.cache` is the app's globally-configured cache store object
  # (backed by whatever cache backend this Rails app is set up to use,
  # e.g. memory, Redis, etc.) — passing it here means the geocoder gem
  # will use that same shared cache rather than maintaining its own
  # separate storage.
  cache: Rails.cache,
  # `cache_options:` takes another nested Hash, opened by the `{` below,
  # configuring details of how entries are stored in the cache chosen
  # above.
  cache_options: {
    # `expiration:` sets how long a cached geocoding result stays valid.
    # `1.day` is Rails/ActiveSupport syntax: `1` is a plain Integer, and
    # `.day` is a method Rails adds onto Integer (via "Core Extensions")
    # that returns an `ActiveSupport::Duration` object representing that
    # many days — here, exactly one day. After this long, a cached result
    # is considered stale and the gem will re-request it from Nominatim.
    # The two trailing spaces before `#` just line up this inline comment
    # under the one on the next setting — purely cosmetic, no effect on
    # Ruby.
    expiration: 1.day,    # How long to cache a geocoding result
    # `prefix:` sets a string prepended to every cache key this gem
    # writes. Since `Rails.cache` above is a SHARED cache also used by
    # other parts of the app for unrelated purposes, this prefix acts as a
    # namespace — it stops geocoding cache entries from ever colliding
    # with (overwriting, or being overwritten by) some other part of the
    # app's cache entries that might coincidentally use the same key.
    prefix:     "storagefinder:geocoder:"
  },
  # This closing brace `}` ends the `cache_options:` inner Hash literal
  # opened above; the trailing comma separates it from the next outer
  # setting.

  # Blank line — visual spacing, no effect on Ruby.

  # Explains the setting below: this controls which unit system the gem
  # uses when it computes distances between two coordinates (e.g. "this
  # storage unit is 3.2 mi away").
  # Units for distance calculations
  # `:mi` is a Symbol selecting miles as the unit; the trailing inline
  # comment `# miles` is a plain-English restatement of what `:mi` means,
  # for anyone unfamiliar with the gem's shorthand.
  units: :mi,  # miles

  # Blank line — visual spacing, no effect on Ruby.

  # Explains the general purpose of the setting below: when a geocoding
  # lookup fails (bad input, network error, service down, etc.), the gem
  # can either raise a Ruby exception (which would crash whatever code
  # called it, unless that code specifically rescues it) or fail silently
  # by returning an empty result. This setting controls which behavior
  # happens, and for which kinds of failures.
  # Whether to throw exceptions on geocoding failure
  # NOTE: this comment describes the setting as if it were a plain boolean
  # ("false = ...") but the value actually assigned below is an empty
  # ARRAY (`[]`), not the boolean `false` — see the "flagged issues" note
  # in this pass's final report; the two are not quite the same thing in
  # this gem's own configuration API, though empty-array does still result
  # in "don't raise for any specific error class," so the practical safety
  # behavior described here is not wrong, just imprecisely worded.
  # false = return empty array on failure (safer)
  # `always_raise:` normally accepts either `true`/`false`, or an Array of
  # specific exception classes that SHOULD always raise even while others
  # are swallowed. Here it's set to `[]` — an empty Array literal, meaning
  # "no exception classes are in the always-raise list" — so, in practice,
  # geocoding failures are swallowed and methods like `Geocoder.search`
  # return an empty result instead of raising.
  always_raise: []
)
# This closing parenthesis `)` ends the argument list — and with it, the
# whole `Geocoder.configure(...)` method call — that was opened several
# lines above.

# Blank line — purely visual spacing, no effect on Ruby.

# `Rails.logger` is the app's shared logging object (writes to the Rails
# log file/stdout depending on environment). `.info` writes a message at
# the "info" severity level. The string argument uses interpolation-free
# plain text here (no `#{}` needed since nothing is dynamic) to record,
# for anyone reading the server's boot log, that geocoding configuration
# above completed and which backend/service is in effect — useful for
# quickly confirming at a glance (without reading this file) which
# geocoding provider a given running instance of the app is using.
Rails.logger.info("[Geocoder] Configured with Nominatim (OpenStreetMap) — no API key required")
