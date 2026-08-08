# =============================================================================
# COMPANY REGISTRY
# =============================================================================
# This is the single place where all company parsers are registered.
# To add a new company:
#   1. Create a parser in app/services/companies/
#   2. Add it to the COMPANIES hash below
#
# The key is what appears in the UI and logs.
# The value is the parser class that handles that company's website.
# =============================================================================

# WHAT is a "service object"? Rails apps typically have "models" (classes
# that represent database tables, like a Unit or a Facility) and
# "controllers" (classes that handle incoming web requests). Sometimes a
# piece of logic doesn't naturally belong to either of those — it's not
# data, and it's not directly answering a web request. A "service object"
# (or "service class") is just a plain Ruby class/module that holds that
# kind of logic in its own dedicated file, so it doesn't get crammed into a
# model or controller where it doesn't belong. This file is one example: it
# holds the logic for "which parser class handles which storage company,"
# which isn't really the job of any single model.
#
# `module CompanyRegistry` defines a Ruby MODULE (not a class) named
# CompanyRegistry. A module can't be instantiated with `.new` the way a
# class can — instead, this module is used purely as a namespace to group
# together a handful of related methods (defined below with `self.` so
# they're callable directly as `CompanyRegistry.some_method`, without ever
# creating an object first).
module CompanyRegistry
  # ---------------------------------------------------------------------------
  # REGISTERED COMPANIES
  # ---------------------------------------------------------------------------
  # Add entries here as new parsers are written.
  # The key must match what you want displayed in the UI.
  # ---------------------------------------------------------------------------

  # `COMPANIES = { ... }` defines a constant (Ruby constants start with a
  # capital letter, and by strong convention ALL_CAPS ones like this are
  # treated as "don't reassign this after it's set once"). Its value is a
  # Ruby Hash literal: `{ key => value, ... }` pairs, where each key is a
  # String (the company's display name) and each value is a class constant
  # (a reference to an actual parser class defined elsewhere in the app,
  # under app/services/companies/).
  COMPANIES = {
    # --- Fully implemented parsers ---
    # Each line maps a human-readable company name (used in the UI, in
    # logs, and as the dropdown/checkbox labels) to the Ruby class that
    # knows how to crawl that specific company's website. `Companies::Foo`
    # is Ruby's "namespaced constant" syntax — it means "the class Foo
    # nested inside the Companies module," matching the file
    # app/services/companies/foo.rb.
    "Extra Space Storage" => Companies::ExtraSpace,
    "Public Storage"      => Companies::PublicStorage,
    "CubeSmart"           => Companies::CubeSmart,
    "Devon Self Storage"  => Companies::DevonSelfStorage,
    "U-Haul Self-Storage" => Companies::UHaul,
    "SmartStop"           => Companies::SmartStop,
    "iStorage"            => Companies::IStorage,     # NSA Storage brand

    # --- Stub — framework ready, parser needs completion ---
    # To complete a stub: run ReconService on the URL, then implement
    # parse_locations and parse_units based on the recon report.
    # This entry points at a parser class that exists but isn't fully
    # written yet — registering it here means it will show up in the UI
    # and be attempted, even though its crawl logic is incomplete.
    "StorAmerica"         => Companies::StorAmerica
  }.freeze

  # `STUBBED_COMPANIES` lists every company name whose parser is a stub
  # (see app/services/companies/stor_america.rb's own header comment) —
  # registered here so the rest of the app knows what CAN be crawled, but
  # whose `parse_locations` always returns `[]` and logs a warning rather
  # than actually scraping anything. Kept as its own small, explicit list
  # (rather than, say, inspecting each parser class for some "stub?" flag)
  # so a human deciding whether a company is really ready has one obvious
  # place to update — the dashboard's company checkboxes (see
  # app/views/dashboard/index.html.erb) read this list to disable
  # StorAmerica's checkbox and label it "(not yet supported)" instead of
  # silently letting a user select it and get zero results back with no
  # explanation.
  STUBBED_COMPANIES = [ "StorAmerica" ].freeze
  # `.freeze` is called on the whole hash literal above. Freezing an object
  # in Ruby makes it immutable — any later attempt to modify this hash
  # (like `COMPANIES["X"] = Y`) would raise a FrozenError instead of
  # silently succeeding. This protects against some other part of the app
  # accidentally mutating the registry at runtime.

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------

  # Returns an array of all registered company names
  # Used to populate the company filter checkboxes on the dashboard
  #
  # `def self.all_company_names` defines a "module method" — the `self.`
  # prefix means this method is called on the module itself
  # (`CompanyRegistry.all_company_names`), not on an instance, because
  # modules like this one are never instantiated.
  def self.all_company_names
    # `COMPANIES.keys` returns just the hash's keys (the company name
    # strings) as an Array, discarding the parser class values. `.sort`
    # then returns a new array with those strings in alphabetical order —
    # this is the method's return value since it's the last expression.
    COMPANIES.keys.sort
  end
  # `end` closes the `def self.all_company_names` method definition above.

  # Returns the parser class for a given company name
  # Raises a clear error if the company isn't registered
  def self.parser_for(company_name)
    # Hash lookup by key: `COMPANIES[company_name]` returns the parser
    # class stored under that name, or Ruby's `nil` if no such key exists.
    parser_class = COMPANIES[company_name]

    # `.nil?` checks whether the lookup above came back empty (company not
    # registered). If so, we want to fail loudly with a helpful message
    # rather than silently returning nil and causing a confusing error
    # somewhere else later.
    if parser_class.nil?
      # `raise ArgumentError, "..."` creates and immediately throws a Ruby
      # exception of type ArgumentError, carrying this message. Raising
      # stops normal execution and unwinds up the call stack until
      # something rescues it (or, if nothing does, the program/job
      # crashes with this message shown).
      raise ArgumentError,
        "[CompanyRegistry] No parser registered for '#{company_name}'. " \
        "Registered companies are: #{all_company_names.join(", ")}. " \
        "To add this company, create a parser in app/services/companies/ " \
        "and add it to COMPANIES in company_registry.rb."
      # The trailing `\` at the end of each string line is Ruby's line
      # continuation inside a string literal made of adjacent string
      # constants — it tells Ruby "this string keeps going on the next
      # line," so the whole message is built as one long String even
      # though it's typed across several source lines.
    end
    # `end` closes the `if parser_class.nil?` block above.

    # If we got past the `if` above without raising, parser_class holds a
    # real class — return it. This is the method's return value.
    parser_class
  end
  # `end` closes the `def self.parser_for` method definition above.

  # Instantiate a parser for a given company name, passing required dependencies
  def self.build_parser(company_name, crawl_run:, browser:, options: {})
    # `crawl_run:`, `browser:`, and `options: {}` are Ruby KEYWORD
    # ARGUMENTS — callers must pass them by name, e.g.
    # `build_parser("CubeSmart", crawl_run: run, browser: b)`. This avoids
    # bugs from mixing up positional argument order. `options: {}` gives
    # `options` a default value of an empty hash if the caller omits it.

    # Look up the parser class first (reuses the method defined above, and
    # will raise the same clear ArgumentError if the company is unknown).
    parser_class = parser_for(company_name)

    # `.new(...)` calls the class's constructor (its `initialize` method)
    # to build an actual parser OBJECT — up to this point we only had the
    # CLASS itself, which is more like a blueprint; `.new` builds one real
    # instance from that blueprint, ready to be used to run a crawl.
    parser_class.new(crawl_run: crawl_run, browser: browser, options: options)
  rescue => e
    # `rescue => e` here is attached directly to the `def...end` method
    # body (no separate `begin` needed — Ruby lets a method body act as an
    # implicit begin/rescue block). It catches ANY StandardError raised
    # anywhere above in this method — including the ArgumentError from
    # `parser_for` if the company name is bad, or any error from the
    # parser class's own `initialize` — and stores it in local variable
    # `e` so we can build a clearer combined error message below.
    raise "Could not build parser for '#{company_name}': #{e.class}: #{e.message}"
    # Re-raises as a new, generic RuntimeError (the default exception type
    # when you `raise` with just a String) whose message wraps the
    # original error's class and message — so callers still see a failure,
    # just with more context about what was being attempted when it broke.
  end
  # `end` closes the `def self.build_parser` method definition above.

  # Returns true if `company_name`'s parser is a known stub (registered, but
  # not yet actually implemented) — see STUBBED_COMPANIES above.
  def self.stubbed?(company_name)
    STUBBED_COMPANIES.include?(company_name)
  end
  # `end` closes the `def self.stubbed?` method definition above.

  # Returns true if we have a parser for this company
  def self.registered?(company_name)
    # `.key?` is a Hash method that returns true/false depending on
    # whether the given key exists in the hash — it doesn't care what the
    # value is, just whether the key is present. By Ruby convention,
    # method names ending in `?` are expected to return true/false.
    COMPANIES.key?(company_name)
  end
  # `end` closes the `def self.registered?` method definition above.
end
# `end` closes the `module CompanyRegistry` definition that started at the
# top of this file.
