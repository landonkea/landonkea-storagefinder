# `require "test_helper"` loads test/test_helper.rb, which boots Rails in
# test mode and loads the fixture data (crawl_runs) used below.
require "test_helper"

# This file tests CompanyRegistry (app/services/company_registry.rb) — the
# module holding the mapping of company display names (like "Public
# Storage") to the parser CLASS (like Companies::PublicStorage) responsible
# for crawling that company's website.
class CompanyRegistryTest < ActiveSupport::TestCase
  test "all_company_names returns every registered company, sorted" do
    # `CompanyRegistry.all_company_names` calls the module method (see
    # company_registry.rb) that returns every registered company's display
    # name as a sorted Array of Strings.
    names = CompanyRegistry.all_company_names
    # `assert_equal names.sort, names` confirms the Array returned is
    # ALREADY in sorted order — `names.sort` builds a freshly re-sorted
    # copy (Ruby's default String sort is alphabetical), and comparing it
    # to the original `names` only passes if they're identical, i.e.
    # `all_company_names` didn't need any re-sorting itself.
    assert_equal names.sort, names
    # `assert_includes names, "Public Storage"` confirms this specific,
    # fully-implemented company name is present somewhere in the list
    # (Minitest's assert_includes checks Array/Enumerable membership).
    assert_includes names, "Public Storage"
    # Confirms the "StorAmerica" stub entry (registered but its parser
    # logic is incomplete — see the COMPANIES hash in company_registry.rb)
    # is ALSO listed here — all_company_names doesn't distinguish complete
    # parsers from stubs, it just lists every registered key.
    assert_includes names, "StorAmerica"
  end
  # `end` closes the "all_company_names returns every registered company,
  # sorted" test block above.

  test "registered? is true for known companies and false for unknown ones" do
    # `assert CompanyRegistry.registered?("Public Storage")` — `assert`
    # alone just requires its argument to be truthy. `registered?` (see
    # company_registry.rb) returns true/false depending on whether the
    # given name exists as a key in the COMPANIES hash.
    assert CompanyRegistry.registered?("Public Storage")
    # `refute` is Minitest's negative counterpart to `assert` — it passes
    # only if its argument is FALSY (false or nil). Confirms a made-up
    # company name correctly returns false rather than true or raising.
    refute CompanyRegistry.registered?("Not A Real Storage Company")
  end
  # `end` closes the "registered? is true for known companies..." test block above.

  test "parser_for returns the parser class for a known company" do
    # `assert_equal Companies::PublicStorage, CompanyRegistry.parser_for("Public Storage")`
    # compares two CLASS OBJECTS for equality (in Ruby, classes themselves
    # are objects, and `==` between two class references checks they're
    # literally the exact same class) — confirming parser_for looks up and
    # returns the correct class from the registry, not just something with
    # a matching name.
    assert_equal Companies::PublicStorage, CompanyRegistry.parser_for("Public Storage")
  end
  # `end` closes the "parser_for returns the parser class for a known
  # company" test block above.

  test "parser_for raises a clear error for an unknown company" do
    # `assert_raises(ArgumentError) { ... }` — same idea as `assert_raises(RuntimeError) do ... end`
    # used elsewhere in this app's tests, but here using Ruby's curly-brace
    # block syntax `{ ... }` instead of `do...end` (both are valid Ruby
    # block syntax; curly braces are common for short, one-line blocks like
    # this). Confirms calling parser_for with an unregistered name raises
    # specifically an ArgumentError (matching the `raise ArgumentError, "..."`
    # line in company_registry.rb), not some other exception type.
    error = assert_raises(ArgumentError) { CompanyRegistry.parser_for("Not A Real Storage Company") }
    # Confirms the error message actually names the unknown company, making
    # it clear to a developer reading logs/output what went wrong and why.
    assert_match(/No parser registered for 'Not A Real Storage Company'/, error.message)
  end
  # `end` closes the "parser_for raises a clear error for an unknown
  # company" test block above.

  test "build_parser instantiates a parser with the given dependencies" do
    # `crawl_run = crawl_runs(:current_completed)` looks up a CrawlRun
    # fixture; `browser = Object.new` creates a plain, generic Ruby object
    # to stand in for a real Playwright browser — fine here since
    # build_parser only needs to PASS this value along to the parser's
    # constructor, it never actually calls browser-specific methods on it
    # itself.
    crawl_run = crawl_runs(:current_completed)
    browser   = Object.new

    # `CompanyRegistry.build_parser("Public Storage", crawl_run:, browser:, options:)`
    # calls the module method that looks up the right parser class AND
    # instantiates it in one step (see company_registry.rb). `options: { sizes: [ "10x10" ] }`
    # is passed through unchanged to the parser's constructor.
    parser = CompanyRegistry.build_parser("Public Storage", crawl_run: crawl_run, browser: browser, options: { sizes: [ "10x10" ] })

    # `assert_instance_of Companies::PublicStorage, parser` confirms the
    # returned object is specifically an INSTANCE of that exact class
    # (as opposed to `assert_kind_of`, which would also accept instances of
    # a subclass) — proving build_parser both found the right class AND
    # successfully called `.new` on it.
    assert_instance_of Companies::PublicStorage, parser
  end
  # `end` closes the "build_parser instantiates a parser with the given
  # dependencies" test block above.

  test "build_parser wraps errors with context about which company failed" do
    error = assert_raises(RuntimeError) do
      # Passing an unregistered company name means the internal call to
      # `parser_for` (inside build_parser) will raise ArgumentError first —
      # but build_parser's own `rescue => e` clause (see company_registry.rb)
      # catches THAT and re-raises a NEW, generic RuntimeError wrapping the
      # original error's class and message. `crawl_run: nil, browser: nil`
      # doesn't matter here since the failure happens before those would
      # ever be used.
      CompanyRegistry.build_parser("Not A Real Storage Company", crawl_run: nil, browser: nil)
    end
    # `end` closes the `assert_raises(RuntimeError) do` block above.
    # Confirms the wrapped error message still names the company that
    # failed, even though the underlying exception type changed from
    # ArgumentError to RuntimeError along the way.
    assert_match(/Could not build parser for 'Not A Real Storage Company'/, error.message)
  end
  # `end` closes the "build_parser wraps errors with context..." test block above.
end
# `end` closes the `class CompanyRegistryTest < ActiveSupport::TestCase`
# definition that started at the top of this file.
