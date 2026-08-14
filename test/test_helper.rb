# `ENV` is Ruby's built-in hash of environment variables (name/value pairs
# set outside the Ruby process, e.g. by the OS or a shell script). This line
# reads the "RAILS_ENV" variable and, if it isn't already set to something,
# sets it to the string "test". `||=` is Ruby's "or-equals" operator: it
# only assigns the right-hand side when the left-hand side is currently nil
# or false, so it won't clobber RAILS_ENV if something already set it (e.g.
# `RAILS_ENV=test bin/rails test` from the command line). This guarantees
# the app boots in test mode, with the test database, test-only config,
# etc., no matter how the test suite was invoked.
ENV["RAILS_ENV"] ||= "test"
# `require_relative` loads another Ruby file, with the path interpreted
# relative to THIS file's own location on disk (unlike plain `require`,
# which searches Ruby's general load path instead). "../config/environment"
# means "go up one directory from test/, then into config/environment.rb",
# that file is what boots the entire Rails application (loading all models,
# initializers, routes, etc.). Nothing else in this app works until this
# line has run.
require_relative "../config/environment"
# Loads Rails' own test-support library. This adds Rails-specific test base
# classes and helpers (like ActiveSupport::TestCase, fixture loading, and
# the assertion methods used throughout every test file in this app) on top
# of plain Minitest (Ruby's built-in testing framework).
require "rails/test_help"
# Loads Minitest's mocking library (from the bundled "minitest-mock" gem).
# "Mocking" and "stubbing" a method both mean the same thing in this
# codebase: temporarily replacing a piece of REAL code with FAKE code for
# the duration of a test, so the test doesn't actually hit a real network
# request, a real browser, or a real paid third-party API, it just
# pretends to, and returns whatever canned result the test tells it to.
# This require makes Minitest's `Object#stub` available. It's not called
# directly very often in this app, though, most tests here instead use the
# custom `stub_any_instance` helper defined further down in this file,
# because plain `Object#stub` can only fake a method on ONE object you
# already have a handle on, and this app's tests often need to fake a
# method on every instance of a class instead (see the big comment on
# `stub_any_instance` below for why).
require "minitest/mock" # from the minitest-mock gem, Object#stub, used to fake out Faraday/network calls

# Facility auto-geocodes on save (see app/models/facility.rb). Left pointed
# at the real Nominatim lookup configured in config/initializers/geocoder.rb,
# every test that saves a Facility without explicit coordinates would hit
# the real network, slow, flaky, and needlessly hammers a third-party rate
# limit. Stub it with a fixed response instead.
#
# `Geocoder.configure(...)` is a setup call from the "geocoder" gem, it
# changes the gem's behavior application-wide, for the rest of this process.
# `lookup: :test` switches the address-lookup service Geocoder uses from a
# real one (Nominatim, in production) to a fake in-memory test double built
# into the gem itself. `ip_lookup: :test` does the same thing for
# IP-address-based lookups. Because this whole file runs once when the test
# suite boots, this stubbing applies to every single test in the app, no
# individual test file needs to remember to set this up itself.
Geocoder.configure(lookup: :test, ip_lookup: :test)
# `Geocoder::Lookup::Test.set_default_stub(...)` tells Geocoder's built-in
# test double WHAT to return whenever anything in the app calls
# `Geocoder.search(...)` or triggers an auto-geocode on save. The argument
# is an Array containing one Hash of fake geocoding result data, Geocoder
# always expects an array back (a real lookup can return multiple candidate
# matches), even though here there's only ever one canned result.
Geocoder::Lookup::Test.set_default_stub(
  [
    {
      # A fake latitude/longitude pair, as a two-element Array: [lat, lng].
      # This particular pair happens to correspond to Gilbert, Arizona,
      # picked because that's the city most of this app's test fixtures use.
      "coordinates"  => [ 33.3528, -111.7890 ],
      # A fake human-readable address string for the geocoded point.
      "address"      => "Gilbert, AZ, USA",
      # Fake state/country fields, filled in exactly as a real Nominatim
      # response would have them, so any code in the app that reads
      # `result.state` or `result.country_code` etc. still works the same
      # way it would against a real lookup.
      "state"        => "Arizona",
      "state_code"   => "AZ",
      "country"      => "United States",
      "country_code" => "US"
    }
  ]
)

# `module ActiveSupport` re-opens Rails' existing ActiveSupport module
# (already defined by the Rails gems loaded above) rather than creating a
# brand new one, Ruby lets you "reopen" any existing module or class and
# add more to it, which is exactly what's happening here.
module ActiveSupport
  # Reopens ActiveSupport::TestCase, the base class that every
  # ActiveSupport-style test class in this app inherits from (directly or
  # indirectly). Adding a method here, like `stub_any_instance` below,
  # makes it available in EVERY test file automatically, without each one
  # having to `require` or `include` anything extra.
  class TestCase
    # Run tests in parallel with specified workers
    # `parallelize(...)` is a Rails/Minitest class method: it splits the
    # test suite across multiple OS processes so tests run concurrently
    # instead of strictly one after another, speeding up the overall test
    # run. `workers: :number_of_processors` tells it to use one worker
    # process per CPU core available on the machine running the tests.
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # "Fixtures" are pre-written sample database rows, defined in YAML files
    # under test/fixtures/ (e.g. test/fixtures/units.yml,
    # test/fixtures/alert_rules.yml). `fixtures :all` loads every fixture
    # file into the test database before each test and makes its rows
    # available via methods named after the fixture file, e.g.
    # `units(:current_gilbert_10x10)` or `alert_rules(:price_drop_rule)`,
    # a fast way to get realistic-looking data into a test without
    # hand-building it inside every single test.
    fixtures :all

    # minitest-mock's Object#stub only targets one specific instance/class
    # method, not "any instance" the way Mocha does, and the code under
    # test builds its Faraday::Connection internally (`Faraday.new(url) do
    # |f| ... end`), so there's no instance to grab a handle on from a test.
    # This patches the method on every instance of `klass` for the duration
    # of the block, then restores the original implementation.
    #
    # WHY this method needs to exist at all: some other Ruby test-mocking
    # gems (like Mocha) ship an "any_instance_of" style stub out of the box,
    # but this app only uses plain Minitest, which doesn't have one. The
    # problem shows up whenever the code being TESTED creates its OWN object
    # internally, for example, AlertDeliveryService builds its own
    # `Faraday::Connection` inside a private method, so a test has no
    # reference to that specific Connection object to call `.stub` on. The
    # fix used here is to temporarily replace the METHOD on the whole
    # CLASS instead of on one instance, so it doesn't matter which instance
    # ends up calling it, every instance of `klass` will run the fake
    # implementation for as long as this helper's block is running.
    #
    # Parameters:
    #   klass         , the class to patch, e.g. Faraday::Connection.
    #   method_name   , a Symbol naming the method to fake, e.g. :post.
    #   implementation, a Proc/lambda: the fake method body to run instead
    #                    of the real one. Because it's captured below with
    #                    `&implementation`, whoever calls stub_any_instance
    #                    must pass this as an actual Ruby block
    #                    (`stub_any_instance(Klass, :method, ->(*) { ... })`
    #                    is how it's used elsewhere in this app's tests,
    #                    the lambda IS the `implementation` argument here).
    # This method ALSO implicitly expects the caller to pass a second block
    # , the real test code that should run while the method is patched,
    # which is invoked below via `yield`.
    def stub_any_instance(klass, method_name, implementation)
      # `klass.instance_method(method_name)` looks up the CURRENT (real,
      # unpatched) implementation of `method_name` on `klass`, returning it
      # as an UnboundMethod object, essentially a saved snapshot of "how
      # this method behaves right now," not yet attached to any particular
      # object. This is kept so the original behavior can be restored once
      # the test is done (see the `ensure` block below).
      original = klass.instance_method(method_name)
      # `klass.send(:define_method, method_name, &implementation)` is Ruby
      # metaprogramming, it REDEFINES `method_name` on `klass` itself, at
      # runtime, using `implementation` (the fake Proc passed in) as the new
      # method body. `define_method` is normally a PRIVATE class method,
      # so `.send(...)` is used to call it anyway from outside the class
      # body, `.send` bypasses Ruby's normal public/private
      # method-visibility check, a common trick for exactly this kind of
      # test/metaprogramming helper. After this line runs, EVERY instance
      # of `klass` anywhere in the app, including ones created deep inside
      # the code under test, where the test has no direct reference to
      # them, will call the fake implementation instead of the real one
      # whenever `method_name` is invoked.
      klass.send(:define_method, method_name, &implementation)
      # Runs whatever block the CALLER of stub_any_instance passed in (the
      # actual test assertions/code that needs the method patched active).
      # Control jumps out to that caller-supplied block, runs it fully, and
      # then execution returns to this point.
      yield
    # `ensure` guarantees the code below it runs no matter what happens
    # above, whether `yield` finished normally, returned early, or raised
    # an exception. This is critical here: without it, a failing test could
    # leave `klass` permanently patched with the fake method for every test
    # that runs afterward, silently breaking unrelated tests in confusing
    # ways.
    ensure
      # Puts the real, original method implementation back, using the same
      # `define_method` metaprogramming trick as above, so `klass` behaves
      # exactly as it did before this helper ever ran.
      klass.send(:define_method, method_name, original)
    end
    # `end` closes the `def stub_any_instance` method definition above.
  end
  # `end` closes the `class TestCase` reopening above.
end
# `end` closes the `module ActiveSupport` reopening that started this block.

# The whole app sits behind HTTP Basic Auth (see ApplicationController) so
# every integration-test request needs valid credentials. get/post/patch/
# put/delete on ActionDispatch::IntegrationTest delegate straight to an
# internal Integration::Session object (see ActionDispatch::Integration::
# Runner) rather than going through an overridable `process` on the test
# class itself, so the header has to be injected at this level, redefining
# these methods directly on the class (rather than `process`) is what
# actually makes every request in every test carry valid credentials without
# each test file having to remember to add a header. See
# test/controllers/authentication_test.rb for a test that exercises the gate
# itself (with credentials deliberately omitted).
#
# "HTTP Basic Auth" is a simple, web-standard way to require a username and
# password on every request: the client (here, the test's simulated
# browser) sends them encoded into a request header called "Authorization"
# on every single request, and the server checks them before doing anything
# else. Without the code below, every integration test that hits a
# controller action would get rejected with a 401 Unauthorized response
# before its actual assertions ever ran, so this exists purely to make
# integration tests "just work" without every test file adding its own
# auth header by hand.
class ActionDispatch::IntegrationTest
  # `%i[get post patch put delete]` is Ruby's "percent-i" array shorthand
  # for an array of Symbols, exactly equivalent to writing
  # `[:get, :post, :patch, :put, :delete]`, just less typing. `.each do
  # |http_method| ... end` loops over that array one HTTP verb at a time,
  # running the block below once per verb, with the local variable
  # `http_method` holding the current one on each pass (first `:get`, then
  # `:post`, and so on).
  %i[get post patch put delete].each do |http_method|
    # `define_method(http_method) do |path, **args| ... end` is
    # metaprogramming again: instead of writing five near-identical `def
    # get(...)`, `def post(...)`, etc. methods by hand, this dynamically
    # defines ONE method per loop iteration, with its NAME coming from the
    # `http_method` variable, so running this single `define_method` call
    # five times (once per entry in the array above) ends up creating five
    # real methods on this class: `get`, `post`, `patch`, `put`, and
    # `delete`. Each defined method takes a required `path` argument plus
    # `**args`, Ruby's "double splat," which scoops up any remaining
    # KEYWORD arguments the caller passed (like `headers:` or `params:`)
    # into a single Hash named `args`, so this wrapper accepts the exact
    # same flexible argument list the real get/post/... methods accept.
    define_method(http_method) do |path, **args|
      # Ensures `args[:headers]` is a Hash (falling back to an empty `{}`
      # if the caller didn't pass any headers at all), then merges in the
      # Basic Auth header. `.reverse_merge(...)` is a Rails helper meaning
      # "merge, but let MY EXISTING keys win over the ones being merged
      # in", the opposite of a plain `.merge`, which would let the new
      # keys win. That means if a specific test already set its own
      # "HTTP_AUTHORIZATION" header on purpose (e.g. to test what happens
      # with bad/missing credentials), that explicit header is preserved
      # instead of being silently overwritten by the default one built by
      # basic_auth_header below.
      args[:headers] = (args[:headers] || {}).reverse_merge(basic_auth_header)
      # `super(path, **args)` calls the ORIGINAL version of this same
      # method, the real `get`/`post`/etc. that Rails' own
      # IntegrationTest machinery defines, passing along the path and the
      # now-modified `args` (headers included). `super` works here because
      # `define_method` is defining a method directly on this class, which
      # inherits the real implementations from its Rails parent class, so
      # "the original method one level up the inheritance chain" is
      # exactly what gets invoked.
      super(path, **args)
    end
    # `end` closes the `define_method(http_method) do |path, **args|`
    # block immediately above, this is the full body of ONE
    # dynamically-defined method (get, or post, or whichever HTTP verb is
    # current in this pass of the loop).
  end
  # `end` closes the `%i[...].each do |http_method|` loop that started
  # above, once this line runs, all five HTTP-verb methods (get, post,
  # patch, put, delete) have been redefined on this class.

  # Builds the actual Basic Auth header value used by the redefined
  # methods above.
  def basic_auth_header
    # Opens a Ruby Hash literal (`{ ... }`) with exactly one key/value pair.
    {
      # `"HTTP_AUTHORIZATION"` is the Rack/Rails-internal name for the
      # standard "Authorization" HTTP header, Rack (the low-level
      # interface Rails is built on) prefixes incoming header names with
      # "HTTP_" and uppercases them, so this is how you set that header
      # when building a request manually like this.
      #
      # `ActionController::HttpAuthentication::Basic.encode_credentials(...)`
      # is a Rails helper that takes a username and a password and returns
      # the properly-formatted Basic Auth header value (technically: the
      # literal text "Basic " followed by "username:password" Base64-encoded,
      # per the HTTP Basic Auth standard).
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        # `Rails.application.credentials.dig(:auth, :username)` reads a
        # value out of the app's encrypted credentials store (see
        # config/credentials.yml.enc, encrypted ciphertext, not directly
        # readable as text on disk). `.dig(:auth, :username)` looks up the
        # nested key `auth:` → `username:` inside that decrypted data,
        # returning nil instead of raising an error if either level of the
        # lookup is missing.
        Rails.application.credentials.dig(:auth, :username),
        # Same idea as the line above, but reading the configured password
        # instead of the username.
        Rails.application.credentials.dig(:auth, :password)
      ) # closes the `encode_credentials(` call opened a few lines above
    } # closes the Hash literal `{` opened above, this one-pair hash is what `basic_auth_header` returns
  end
  # `end` closes the `def basic_auth_header` method definition above.
end
# `end` closes the `class ActionDispatch::IntegrationTest` reopening that
# started this whole section.
