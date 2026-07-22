ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock" # from the minitest-mock gem — Object#stub, used to fake out Faraday/network calls

# Facility auto-geocodes on save (see app/models/facility.rb). Left pointed
# at the real Nominatim lookup configured in config/initializers/geocoder.rb,
# every test that saves a Facility without explicit coordinates would hit
# the real network — slow, flaky, and needlessly hammers a third-party rate
# limit. Stub it with a fixed response instead.
Geocoder.configure(lookup: :test, ip_lookup: :test)
Geocoder::Lookup::Test.set_default_stub(
  [
    {
      "coordinates"  => [ 33.3528, -111.7890 ],
      "address"      => "Gilbert, AZ, USA",
      "state"        => "Arizona",
      "state_code"   => "AZ",
      "country"      => "United States",
      "country_code" => "US"
    }
  ]
)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # minitest-mock's Object#stub only targets one specific instance/class
    # method, not "any instance" the way Mocha does — and the code under
    # test builds its Faraday::Connection internally (`Faraday.new(url) do
    # |f| ... end`), so there's no instance to grab a handle on from a test.
    # This patches the method on every instance of `klass` for the duration
    # of the block, then restores the original implementation.
    def stub_any_instance(klass, method_name, implementation)
      original = klass.instance_method(method_name)
      klass.send(:define_method, method_name, &implementation)
      yield
    ensure
      klass.send(:define_method, method_name, original)
    end
  end
end

# The whole app sits behind HTTP Basic Auth (see ApplicationController) so
# every integration-test request needs valid credentials. get/post/patch/
# put/delete on ActionDispatch::IntegrationTest delegate straight to an
# internal Integration::Session object (see ActionDispatch::Integration::
# Runner) rather than going through an overridable `process` on the test
# class itself, so the header has to be injected at this level — redefining
# these methods directly on the class (rather than `process`) is what
# actually makes every request in every test carry valid credentials without
# each test file having to remember to add a header. See
# test/controllers/authentication_test.rb for a test that exercises the gate
# itself (with credentials deliberately omitted).
class ActionDispatch::IntegrationTest
  %i[get post patch put delete].each do |http_method|
    define_method(http_method) do |path, **args|
      args[:headers] = (args[:headers] || {}).reverse_merge(basic_auth_header)
      super(path, **args)
    end
  end

  def basic_auth_header
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        Rails.application.credentials.dig(:auth, :username),
        Rails.application.credentials.dig(:auth, :password)
      )
    }
  end
end
