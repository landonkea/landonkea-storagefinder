require "test_helper"

class CompanyRegistryTest < ActiveSupport::TestCase
  test "all_company_names returns every registered company, sorted" do
    names = CompanyRegistry.all_company_names
    assert_equal names.sort, names
    assert_includes names, "Public Storage"
    assert_includes names, "StorAmerica"
  end

  test "registered? is true for known companies and false for unknown ones" do
    assert CompanyRegistry.registered?("Public Storage")
    refute CompanyRegistry.registered?("Not A Real Storage Company")
  end

  test "parser_for returns the parser class for a known company" do
    assert_equal Companies::PublicStorage, CompanyRegistry.parser_for("Public Storage")
  end

  test "parser_for raises a clear error for an unknown company" do
    error = assert_raises(ArgumentError) { CompanyRegistry.parser_for("Not A Real Storage Company") }
    assert_match(/No parser registered for 'Not A Real Storage Company'/, error.message)
  end

  test "build_parser instantiates a parser with the given dependencies" do
    crawl_run = crawl_runs(:current_completed)
    browser   = Object.new

    parser = CompanyRegistry.build_parser("Public Storage", crawl_run: crawl_run, browser: browser, options: { sizes: [ "10x10" ] })

    assert_instance_of Companies::PublicStorage, parser
  end

  test "build_parser wraps errors with context about which company failed" do
    error = assert_raises(RuntimeError) do
      CompanyRegistry.build_parser("Not A Real Storage Company", crawl_run: nil, browser: nil)
    end
    assert_match(/Could not build parser for 'Not A Real Storage Company'/, error.message)
  end
end
