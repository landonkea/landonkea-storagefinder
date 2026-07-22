# =============================================================================
# BASE PARSER
# =============================================================================
# Every company parser inherits from this class.
# It provides shared functionality so each company parser only has to implement
# the parts that are unique to that company's website.
#
# TO ADD A NEW COMPANY:
#   1. Create a new file in app/services/companies/
#   2. Name it snake_case matching the company (e.g. my_storage_co.rb)
#   3. Inherit from BaseParser
#   4. Implement the required methods listed below
#   5. Register it in CompanyRegistry (app/services/company_registry.rb)
#
# REQUIRED METHODS TO IMPLEMENT IN SUBCLASS:
#   - company_name    → String, e.g. "Extra Space Storage"
#   - company_slug    → String, e.g. "extra_space" (used in logs and file names)
#   - search_url(lat, lng, radius_miles) → String URL to search for locations
#   - parse_locations(page) → Array of { name:, address:, city:, state:, zip:, phone:, url: }
#   - parse_units(page, facility) → Array of unit attribute hashes
# =============================================================================

class Companies::BaseParser
  # ---------------------------------------------------------------------------
  # CONFIGURATION — subclasses can override these
  # ---------------------------------------------------------------------------

  # How many times to retry a failed page load before giving up
  MAX_RETRIES = 3

  # How long to wait between retries (in milliseconds)
  RETRY_DELAY_MS = 3000

  # How long to wait for a page to load before timing out (in milliseconds)
  PAGE_TIMEOUT_MS = 30_000

  # How long to wait after a page loads for JS to finish rendering (ms)
  JS_SETTLE_DELAY_MS = 2000

  # ---------------------------------------------------------------------------
  # INITIALIZER
  # ---------------------------------------------------------------------------
  # crawl_run: the CrawlRun record this parser is working on behalf of
  # browser:   a Playwright browser instance shared across parsers
  # options:   hash of filter options from the user's crawl settings
  # ---------------------------------------------------------------------------
  def initialize(crawl_run:, browser:, options: {})
    @crawl_run = crawl_run    # The CrawlRun record — used for logging
    @browser   = browser      # Playwright browser — used to open pages
    @options   = options      # Filter options (sizes, climate_controlled, etc.)

    # Create a logger tagged with this company's name so log lines are identifiable
    @logger = Rails.logger.tagged(company_name)
  end

  # ---------------------------------------------------------------------------
  # MAIN ENTRY POINT
  # ---------------------------------------------------------------------------
  # This is the method called by the CrawlJob to run this company's parser.
  # Subclasses should NOT override this — override parse_locations and parse_units instead.
  # ---------------------------------------------------------------------------
  def run(search_lat:, search_lng:, radius_miles:)
    log_info("Starting crawl for #{company_name}")

    facilities_saved = 0
    units_saved      = 0

    begin
      # Step 1: Open the search page and get a list of facility locations
      log_info("Opening search URL for coordinates #{search_lat}, #{search_lng}")

      search_page_url = search_url(search_lat, search_lng, radius_miles)
      page = open_page(search_page_url)

      # Step 2: Extract location data from the search results page
      log_info("Parsing location list from search results page")
      locations = parse_locations(page)

      if locations.empty?
        log_warning("No locations found on search page. The page layout may have changed.")
        log_warning("URL: #{search_page_url}")
        take_error_screenshot(page, "no_locations_found")
        return { facilities: 0, units: 0 }
      end

      log_info("Found #{locations.length} location(s) listed")

      # Step 3: For each location, visit its page and extract unit prices
      locations.each_with_index do |location_data, index|
        log_info("Processing location #{index + 1}/#{locations.length}: #{location_data[:name]}")

        begin
          # Find or create the Facility record in the database
          facility = upsert_facility(location_data)

          # Visit the facility's pricing page
          facility_page_url = location_data[:url]
          if facility_page_url.blank?
            log_warning("No URL for #{location_data[:name]} — skipping unit pricing")
            next
          end

          facility_page = open_page(facility_page_url)

          # Extract unit data from the facility page
          raw_units = parse_units(facility_page, facility)

          if raw_units.empty?
            log_warning("No units found at #{location_data[:name]}. Page may need updating.")
            take_error_screenshot(facility_page, "no_units_#{facility.id}")
          else
            # Step 4: Filter units based on user's filter options
            filtered_units = apply_filters(raw_units)

            log_info("Found #{raw_units.length} units, #{filtered_units.length} match filters at #{location_data[:name]}")

            # Step 5: Save matching units to the database
            filtered_units.each do |unit_data|
              save_unit(unit_data, facility)
              units_saved += 1
            end

            facilities_saved += 1
          end

        rescue Playwright::TimeoutError => e
          # Page took too long to load
          log_error(
            "Timeout loading page for #{location_data[:name]}: #{e.message}. " \
            "This can happen on slow connections or slow hardware. Try increasing " \
            "crawl_delay_between_requests_ms in Settings.",
            url: location_data[:url]
          )

        rescue => e
          # Any other error on this specific location — log it and keep going
          log_error(
            "Error processing #{location_data[:name]}: #{e.class}: #{e.message}. " \
            "Backtrace: #{e.backtrace.first(3).join(' | ')}",
            url: location_data[:url]
          )
        end

        # Polite delay between location requests — avoids overwhelming the site
        # and helps with rate limiting on slow hardware
        delay_ms = Setting.get("crawl_delay_between_requests_ms", default: 2000).to_i
        sleep(delay_ms / 1000.0)
      end

      log_success("Completed #{company_name}: #{facilities_saved} facilities, #{units_saved} units saved")
      { facilities: facilities_saved, units: units_saved }

    rescue Playwright::TimeoutError => e
      # The initial search page timed out — can't get any locations
      log_error(
        "Timeout on search page for #{company_name}. " \
        "URL: #{search_url(search_lat, search_lng, radius_miles)}. " \
        "Error: #{e.message}"
      )
      { facilities: 0, units: 0, error: e.message }

    rescue => e
      # Catch-all for unexpected errors — log everything we know
      log_error(
        "Unexpected error crawling #{company_name}: #{e.class}: #{e.message}. " \
        "Full backtrace: #{e.backtrace.join("\n")}"
      )
      { facilities: 0, units: 0, error: e.message }
    end
  end

  # ---------------------------------------------------------------------------
  # METHODS THAT SUBCLASSES MUST IMPLEMENT
  # ---------------------------------------------------------------------------

  # Returns the company's full display name
  # Example: "Extra Space Storage"
  def company_name
    raise NotImplementedError,
      "#{self.class.name} must implement company_name. " \
      "Return a string like 'Extra Space Storage'."
  end

  # Returns a short identifier for this company used in file names and logs
  # Example: "extra_space"
  def company_slug
    raise NotImplementedError,
      "#{self.class.name} must implement company_slug. " \
      "Return a short snake_case string like 'extra_space'."
  end

  # Returns the URL to search for locations near the given coordinates
  # Must return a String URL
  def search_url(lat, lng, radius_miles)
    raise NotImplementedError,
      "#{self.class.name} must implement search_url(lat, lng, radius_miles). " \
      "Return the URL the company uses to list nearby locations."
  end

  # Parses the location list from a search results page
  # page: a Playwright page object (you can call page.query_selector etc.)
  # Must return an Array of hashes with these keys:
  #   name:, address:, city:, state:, zip:, phone: (optional), url:
  def parse_locations(page)
    raise NotImplementedError,
      "#{self.class.name} must implement parse_locations(page). " \
      "Return an array of location hashes with keys: name, address, city, state, zip, url."
  end

  # Parses unit pricing from a facility's detail page
  # page: a Playwright page object
  # facility: the Facility ActiveRecord object for this location
  # Must return an Array of hashes with unit attributes
  def parse_units(page, facility)
    raise NotImplementedError,
      "#{self.class.name} must implement parse_units(page, facility). " \
      "Return an array of unit attribute hashes."
  end

  # ---------------------------------------------------------------------------
  # SHARED HELPER METHODS — available to all subclasses via inheritance
  # ---------------------------------------------------------------------------
  protected

  # Opens a URL in a new browser page with automatic retry logic
  # Returns the Playwright page object
  def open_page(url, retries: MAX_RETRIES)
    attempt = 0

    begin
      attempt += 1
      log_info("Opening page (attempt #{attempt}/#{retries + 1}): #{url}")

      # Create a new browser tab
      page = @browser.new_page

      # Set a realistic User-Agent so the site doesn't immediately block us
      page.set_extra_http_headers({
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      })

      # Navigate to the URL. We used to wait for "networkidle" here, but modern
      # sites keep background connections open indefinitely (analytics, chat
      # widgets, polling) so network activity never actually goes idle — that
      # made every page load hit the full timeout. "domcontentloaded" fires as
      # soon as the HTML is parsed; each parser's own wait_for_selector call
      # (in parse_locations/parse_units) handles waiting for the real content.
      page.goto(url, waitUntil: "domcontentloaded", timeout: PAGE_TIMEOUT_MS)

      # Additional wait for any animations or delayed JS rendering
      page.wait_for_timeout(JS_SETTLE_DELAY_MS)

      log_info("Page loaded successfully: #{url}")
      page

    rescue Playwright::TimeoutError => e
      if attempt <= retries
        log_warning(
          "Page load timed out (attempt #{attempt}/#{retries + 1}). " \
          "Waiting #{RETRY_DELAY_MS}ms before retry. URL: #{url}"
        )
        sleep(RETRY_DELAY_MS / 1000.0)
        retry
      else
        log_error(
          "Page load failed after #{retries + 1} attempts. Giving up. " \
          "URL: #{url}. Error: #{e.message}"
        )
        raise  # Re-raise so the caller can handle it
      end

    rescue => e
      if attempt <= retries
        log_warning(
          "Unexpected error loading page (attempt #{attempt}/#{retries + 1}): " \
          "#{e.class}: #{e.message}. URL: #{url}"
        )
        sleep(RETRY_DELAY_MS / 1000.0)
        retry
      else
        raise
      end
    end
  end

  # Safely extracts text from a CSS selector on a page
  # Returns nil (not an error) if the element doesn't exist
  # This is much safer than page.query_selector(...).text_content which crashes if nil
  #
  # Usage: safe_text(page, ".price-label")
  def safe_text(page_or_element, selector)
    element = page_or_element.query_selector(selector)
    return nil if element.nil?

    text = element.text_content
    text&.strip&.presence  # strip whitespace, return nil if empty string
  rescue => e
    log_warning("Could not read text from selector '#{selector}': #{e.message}")
    nil
  end

  # Safely extracts an attribute value from an element
  # Usage: safe_attr(page, "a.booking-link", "href")
  def safe_attr(page_or_element, selector, attribute)
    element = page_or_element.query_selector(selector)
    return nil if element.nil?

    element.get_attribute(attribute)&.strip&.presence
  rescue => e
    log_warning("Could not read attribute '#{attribute}' from selector '#{selector}': #{e.message}")
    nil
  end

  # Safely extracts text from all matching elements (returns an array)
  # Usage: safe_all_text(page, ".unit-row .price")
  def safe_all_text(page_or_element, selector)
    elements = page_or_element.query_selector_all(selector)
    return [] if elements.empty?

    elements.map { |el| el.text_content&.strip&.presence }.compact
  rescue => e
    log_warning("Could not read all text from selector '#{selector}': #{e.message}")
    []
  end

  # Parse a price string like "$89.00/mo" or "89" into a decimal
  # Returns nil if it can't be parsed
  def parse_price(price_string)
    return nil if price_string.blank?

    # Remove everything except digits and decimal point
    cleaned = price_string.to_s.gsub(/[^\d.]/, "")
    return nil if cleaned.blank?

    price = cleaned.to_f
    return nil if price <= 0

    price.round(2)
  rescue => e
    log_warning("Could not parse price from '#{price_string}': #{e.message}")
    nil
  end

  # Parse a size string like "10' x 20'" or "10X20" into normalized "10x20" format
  def parse_size(size_string)
    return nil if size_string.blank?

    # Extract just the numbers — handles formats like "10x20", "10' x 20'", "10 X 20 ft"
    numbers = size_string.to_s.scan(/\d+/).map(&:to_i)

    # We need exactly two numbers (width and depth)
    return nil unless numbers.length >= 2

    "#{numbers[0]}x#{numbers[1]}"
  rescue => e
    log_warning("Could not parse size from '#{size_string}': #{e.message}")
    nil
  end

  # Takes a screenshot and saves it to the logs directory
  # Used automatically when errors occur so you can see what went wrong
  def take_error_screenshot(page, label)
    filename = "logs/#{company_slug}_#{label}_#{Time.current.strftime("%Y%m%d_%H%M%S")}.png"

    begin
      page.screenshot(path: Rails.root.join(filename).to_s)
      log_info("Error screenshot saved: #{filename}")
    rescue => e
      log_warning("Could not save screenshot: #{e.message}")
    end
  end

  # Find or create a Facility record from location data
  # Uses external_id or (company + address) as the unique identifier
  def upsert_facility(location_data)
    # Try to find an existing facility by external_id first (most reliable)
    facility = if location_data[:external_id].present?
      Facility.find_or_initialize_by(
        company:     company_name,
        external_id: location_data[:external_id]
      )
    else
      # Fall back to matching on company + address (less reliable but still works)
      Facility.find_or_initialize_by(
        company: company_name,
        address: location_data[:address],
        city:    location_data[:city],
        state:   location_data[:state]
      )
    end

    # Update all fields (whether new or existing record)
    facility.assign_attributes(
      name:         location_data[:name]         || "#{company_name} - #{location_data[:city]}",
      address:      location_data[:address],
      city:         location_data[:city],
      state:        location_data[:state],
      zip:          location_data[:zip],
      phone:        location_data[:phone],
      facility_url: location_data[:url],
      external_id:  location_data[:external_id]
    )

    if facility.save
      facility
    else
      # If save fails, log what went wrong and raise so the caller knows
      error_messages = facility.errors.full_messages.join(", ")
      raise "Could not save facility '#{location_data[:name]}': #{error_messages}"
    end
  end

  # Save a unit to the database associated with a facility and the current crawl run
  def save_unit(unit_data, facility)
    unit = Unit.new(
      facility:    facility,
      crawl_run:   @crawl_run,
      collected_at: Time.current,
      **unit_data  # Spread all the unit attributes from the hash
    )

    unless unit.save
      error_messages = unit.errors.full_messages.join(", ")
      log_warning(
        "Could not save unit (#{unit_data[:size]} at #{facility.name}): #{error_messages}"
      )
    end

    unit
  end

  # Filter raw unit data through the user's filter options
  # Returns only units that match
  def apply_filters(raw_units)
    # What sizes did the user select?
    selected_sizes = @options[:sizes] || Unit::DEFAULT_SIZES

    # What unit types to exclude?
    excluded_types = @options[:excluded_types] || Unit::EXCLUDED_TYPES

    raw_units.select do |unit|
      # Must be climate controlled (if filter is on)
      next false if @options[:climate_controlled] && !unit[:climate_controlled]

      # Must not be an excluded type (parking, RV, boat, locker, etc. — see
      # Unit::EXCLUDED_TYPES). Note: we do NOT hard-exclude drive-up/outdoor
      # units here — there's no UI control for that, so silently dropping
      # them just loses real inventory the user asked to see.
      next false if excluded_types.include?(unit[:unit_type].to_s.downcase)

      # Must match one of the selected sizes
      size = parse_size(unit[:size].to_s)
      next false unless size

      parts = size.split("x").map(&:to_i)
      next false unless parts.length == 2

      width, depth = parts
      min_width = 10
      min_depth  = 10

      next false if width < min_width || depth < min_depth

      # If specific sizes are selected, include this unit if it belongs to
      # the closest selected size bucket. Real listings come in far more
      # granular sizes than the 5 standard checkboxes (10x12, 10x24, 12x20,
      # ...) — matching the *exact* string would silently drop almost
      # everything that isn't precisely "10x10"/"10x15"/etc. Bucketing by
      # square footage keeps every unit >= 10x10 visible under whichever
      # standard size it's closest to.
      if selected_sizes.present?
        next false unless selected_sizes.include?(size_bucket(width, depth))
      end

      true  # This unit passes all filters
    end
  end

  # Maps an arbitrary WxD unit size to the closest of Unit::DEFAULT_SIZES,
  # by comparing square footage. e.g. a real 10x12 (120 sqft) is closer to
  # 10x10 (100 sqft) than 10x15 (150 sqft), so it buckets as "10x10".
  def size_bucket(width, depth)
    sqft = width * depth

    Unit::DEFAULT_SIZES.min_by do |standard_size|
      sw, sd = standard_size.split("x").map(&:to_i)
      (sqft - (sw * sd)).abs
    end
  end

  # ---------------------------------------------------------------------------
  # LOGGING HELPERS — delegate to the CrawlRun model's log methods
  # ---------------------------------------------------------------------------

  def log_info(message, url: nil)
    @crawl_run.log_info(message, company: company_name, url: url)
  end

  def log_warning(message, url: nil, retry_count: 0)
    @crawl_run.log_warning(message, company: company_name, url: url, retry_count: retry_count)
  end

  def log_error(message, url: nil, retry_count: 0)
    @crawl_run.log_error(message, company: company_name, url: url, retry_count: retry_count)
  end

  def log_success(message, url: nil)
    @crawl_run.log_success(message, company: company_name, url: url)
  end
end
