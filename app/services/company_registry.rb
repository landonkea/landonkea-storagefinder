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

module CompanyRegistry
  # ---------------------------------------------------------------------------
  # REGISTERED COMPANIES
  # ---------------------------------------------------------------------------
  # Add entries here as new parsers are written.
  # The key must match what you want displayed in the UI.
  # ---------------------------------------------------------------------------
  COMPANIES = {
    # --- Fully implemented parsers ---
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
    "StorAmerica"         => Companies::StorAmerica
  }.freeze

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------

  # Returns an array of all registered company names
  # Used to populate the company filter checkboxes on the dashboard
  def self.all_company_names
    COMPANIES.keys.sort
  end

  # Returns the parser class for a given company name
  # Raises a clear error if the company isn't registered
  def self.parser_for(company_name)
    parser_class = COMPANIES[company_name]

    if parser_class.nil?
      raise ArgumentError,
        "[CompanyRegistry] No parser registered for '#{company_name}'. " \
        "Registered companies are: #{all_company_names.join(", ")}. " \
        "To add this company, create a parser in app/services/companies/ " \
        "and add it to COMPANIES in company_registry.rb."
    end

    parser_class
  end

  # Instantiate a parser for a given company name, passing required dependencies
  def self.build_parser(company_name, crawl_run:, browser:, options: {})
    parser_class = parser_for(company_name)
    parser_class.new(crawl_run: crawl_run, browser: browser, options: options)
  rescue => e
    raise "Could not build parser for '#{company_name}': #{e.class}: #{e.message}"
  end

  # Returns true if we have a parser for this company
  def self.registered?(company_name)
    COMPANIES.key?(company_name)
  end
end
