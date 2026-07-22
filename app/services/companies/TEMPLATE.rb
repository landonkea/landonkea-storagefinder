# =============================================================================
# COMPANY PARSER TEMPLATE
# =============================================================================
# Copy this file, rename it to your company's snake_case name (e.g. my_storage.rb)
# then implement the 4 required methods below.
#
# After creating the file, register your company in:
#   app/services/company_registry.rb
#
# Then run the recon tool to get current selectors:
#   rails runner "ReconService.run('https://www.yourcompany.com/locations/?city=gilbert&state=az')"
# =============================================================================

class Companies::YourCompanyName < Companies::BaseParser
  BASE_URL = "https://www.yourcompany.com"

  # The display name shown in the UI and exports
  # Example: "CubeSmart Self Storage"
  def company_name
    "Your Company Name"
  end

  # Short identifier for logs and file names — no spaces, snake_case
  # Example: "cubesmart"
  def company_slug
    "your_company_name"
  end

  # The URL that shows storage locations near the given coordinates
  # lat and lng are GPS coordinates (e.g. 33.3528, -111.7890)
  # radius_miles is how far out to search
  #
  # Tips:
  #   - Use the recon tool to find the right URL format
  #   - Some companies use lat/lng, some use a zip code
  #   - Some companies need a two-step search (enter city, then wait for results)
  def search_url(lat, lng, radius_miles)
    # Replace this with the actual search URL pattern for this company
    # Example: "#{BASE_URL}/locations/?lat=#{lat}&lng=#{lng}&radius=#{radius_miles}"
    raise NotImplementedError, "Implement search_url for #{company_name}"
  end

  # Parse the list of storage locations from the search results page
  # `page` is a Playwright page object — you can call page.query_selector, etc.
  #
  # Must return an Array of hashes with these keys:
  #   name:        String  — facility display name (required)
  #   address:     String  — street address (required)
  #   city:        String  — city name (required)
  #   state:       String  — 2-letter state code (required)
  #   zip:         String  — ZIP code (required)
  #   phone:       String  — phone number (optional)
  #   url:         String  — URL to the facility's pricing page (required)
  #   external_id: String  — company's own ID for this location (optional, prevents duplicates)
  def parse_locations(page)
    locations = []

    begin
      # STEP 1: Wait for results to appear
      # Replace ".result-list" with the actual selector from the recon report
      page.wait_for_selector(".result-list", timeout: 15_000)

      # STEP 2: Find all location cards
      cards = page.query_selector_all(".location-card")

      if cards.empty?
        log_warning("No location cards found. Check selectors with ReconService.")
        take_error_screenshot(page, "no_cards")
        return []
      end

      # STEP 3: Extract data from each card
      cards.each_with_index do |card, idx|
        begin
          name    = safe_text(card, ".facility-name")   # Replace with real selector
          address = safe_text(card, ".street-address")  # Replace with real selector
          city    = safe_text(card, ".city")            # Replace with real selector
          state   = safe_text(card, ".state")           # Replace with real selector
          zip     = safe_text(card, ".zip")             # Replace with real selector
          phone   = safe_text(card, ".phone")           # Replace with real selector (can be nil)
          url     = safe_attr(card, "a", "href")        # Replace with real selector
          url     = "#{BASE_URL}#{url}" if url&.start_with?("/")

          next if name.blank? || address.blank?

          locations << {
            name:        name,
            address:     address,
            city:        city || "",
            state:       state || "AZ",
            zip:         zip || "",
            phone:       phone,
            url:         url,
            external_id: nil  # Add if the company exposes an ID
          }

        rescue => e
          log_warning("Error parsing card ##{idx + 1}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for location list: #{e.message}")
      take_error_screenshot(page, "timeout")
    rescue => e
      log_error("Error in parse_locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "error")
    end

    locations
  end

  # Parse unit sizes and prices from a facility's pricing page
  # `page` is a Playwright page object
  # `facility` is the Facility ActiveRecord object for this location
  #
  # Must return an Array of hashes with these keys:
  #   size:               String   — e.g. "10x20" (required)
  #   monthly_price:      Float    — regular monthly rate in dollars (optional)
  #   web_special_price:  Float    — promotional/online price (optional)
  #   web_special_note:   String   — description of the special (optional)
  #   admin_fee:          Float    — one-time admin fee in dollars (optional)
  #   insurance_note:     String   — insurance requirement note (optional)
  #   climate_controlled: Boolean  — true if climate controlled (required)
  #   available:          Boolean  — true if unit is available (required)
  #   drive_up:           Boolean  — true if outdoor/drive-up access (required)
  #   indoor:             Boolean  — true if indoor unit (required)
  #   unit_type:          String   — "standard", "locker", "parking", etc. (required)
  #   booking_url:        String   — URL to reserve this unit (optional)
  def parse_units(page, facility)
    units = []

    begin
      # STEP 1: Wait for unit grid to render
      page.wait_for_selector(".unit-list", timeout: 15_000)  # Replace with real selector

      # STEP 2: Find all unit elements
      unit_els = page.query_selector_all(".unit-item")  # Replace with real selector

      if unit_els.empty?
        log_warning("No units found at #{facility.name}. Run ReconService on: #{facility.facility_url}")
        return []
      end

      # STEP 3: Extract data from each unit
      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".unit-size")    # Replace with real selector
          size     = parse_size(raw_size)
          next if size.blank?

          price_text    = safe_text(el, ".price")   # Replace with real selector
          monthly_price = parse_price(price_text)

          # Detect climate control from text or data attributes
          features      = safe_text(el, ".features") || ""
          cc            = features.downcase.include?("climate")

          # Detect drive-up
          drive_up      = features.downcase.include?("drive-up") ||
                          features.downcase.include?("outdoor")

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  nil,     # Add if the company shows a web price
            web_special_note:   nil,
            admin_fee:          nil,
            insurance_note:     nil,
            climate_controlled: cc,
            available:          true,    # Update if the site shows availability
            drive_up:           drive_up,
            indoor:             !drive_up,
            unit_type:          "standard",  # Update if you detect type from page
            booking_url:        facility.facility_url
          }

        rescue => e
          log_warning("Error parsing unit ##{idx + 1} at #{facility.name}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout loading units at #{facility.name}: #{e.message}")
      take_error_screenshot(page, "timeout_#{facility.id}")
    rescue => e
      log_error("Error in parse_units for #{facility.name}: #{e.class}: #{e.message}")
    end

    units
  end
end
