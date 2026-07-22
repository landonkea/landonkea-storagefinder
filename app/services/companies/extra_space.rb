# =============================================================================
# EXTRA SPACE STORAGE PARSER
# =============================================================================
# Crawls extraspace.com to find storage facilities and unit pricing.
#
# Website behavior notes:
#   - Location search uses a lat/lng based URL parameter
#   - Location list renders via JavaScript (must wait for it)
#   - Unit pricing page uses React — prices load after initial page render
#   - "Web Rate" is the online-only discounted price
#   - "Street Rate" is the walk-in regular price
#   - We capture both and store web rate as web_special_price
#
# If the site layout changes and this parser breaks, run the recon tool:
#   rails runner "ReconService.run('https://www.extraspace.com/storage/find-storage/in/gilbert-az/')"
# =============================================================================

class Companies::ExtraSpace < Companies::BaseParser
  # The base URL for Extra Space Storage searches
  BASE_URL = "https://www.extraspace.com"

  # How many miles to expand the search if no results come back initially
  FALLBACK_RADIUS_EXPANSION = 10

  def company_name
    "Extra Space Storage"
  end

  def company_slug
    "extra_space"
  end

  # Build the search URL for a given lat/lng and radius
  # Extra Space uses lat/lng in the query string
  def search_url(lat, lng, radius_miles)
    # Extra Space's search endpoint accepts lat, lng, and radius
    "#{BASE_URL}/storage/find-storage/?lat=#{lat}&lng=#{lng}&radius=#{radius_miles}&sort=distance"
  end

  # Parse the list of storage locations from the search results page
  # Returns an array of location hashes
  def parse_locations(page)
    locations = []

    begin
      # Wait for the location list to appear — it renders via JavaScript
      # The selector ".facility-results-list" is the container for all results
      log_info("Waiting for location results to render...")

      page.wait_for_selector(
        ".facility-results-list, .no-results-message, [data-testid='facility-card']",
        timeout: 15_000
      )

      # Check if "no results" message appeared — means no locations in this area
      no_results = page.query_selector(".no-results-message, [data-testid='no-results']")
      if no_results
        log_warning("Extra Space returned 'no results' for this search area")
        return []
      end

      # Find all facility cards in the results list
      # Each card represents one storage location
      facility_cards = page.query_selector_all(
        "[data-testid='facility-card'], .facility-card, .search-result-item"
      )

      if facility_cards.empty?
        log_warning(
          "Could not find facility cards on Extra Space search page. " \
          "The site may have updated its layout. " \
          "Expected selector: '[data-testid=facility-card]'. " \
          "Run ReconService to get current selectors."
        )
        take_error_screenshot(page, "no_facility_cards")
        return []
      end

      log_info("Found #{facility_cards.length} facility cards — extracting details")

      facility_cards.each_with_index do |card, index|
        begin
          # Extract the facility name
          name = safe_text(card, "[data-testid='facility-name'], .facility-name, h3")

          # Extract the address — Extra Space usually has separate elements for each part
          street  = safe_text(card, "[data-testid='address-street'], .address-street, .street-address")
          city    = safe_text(card, "[data-testid='address-city'], .address-city")
          state   = safe_text(card, "[data-testid='address-state'], .address-state")
          zip     = safe_text(card, "[data-testid='address-zip'], .address-zip, .postal-code")

          # Phone number (may not always be present on the list view)
          phone   = safe_text(card, "[data-testid='phone'], .facility-phone, .phone-number")

          # The link to this facility's detail/pricing page
          link_element = card.query_selector("a[href*='/storage/find-storage/']")
          relative_url = link_element&.get_attribute("href")
          facility_url = relative_url ? "#{BASE_URL}#{relative_url}" : nil

          # Extract Extra Space's internal facility ID from the URL or data attributes
          # This helps us avoid creating duplicates on future crawls
          external_id = card.get_attribute("data-facility-id") ||
                        card.get_attribute("data-id") ||
                        extract_id_from_url(facility_url)

          # Skip this card if we couldn't get a valid name or address
          if name.blank? || street.blank?
            log_warning(
              "Facility card ##{index + 1} is missing name or street address — skipping. " \
              "This may indicate a layout change in this part of the page."
            )
            next
          end

          locations << {
            name:        name,
            address:     street,
            city:        city || "",
            state:       state || "AZ",
            zip:         zip || "",
            phone:       phone,
            url:         facility_url,
            external_id: external_id
          }

          log_info("  ✓ Location #{index + 1}: #{name} — #{street}, #{city}")

        rescue => e
          log_warning("Error parsing facility card ##{index + 1}: #{e.class}: #{e.message}")
          # Keep going — don't let one bad card kill the whole list
        end
      end

    rescue Playwright::TimeoutError => e
      log_error(
        "Timed out waiting for Extra Space location results to render. " \
        "The page took longer than 15 seconds. " \
        "This can happen on slow hardware or slow internet. " \
        "Try increasing PAGE_TIMEOUT_MS in base_parser.rb. " \
        "Error: #{e.message}"
      )
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing Extra Space location list: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  # Parse unit sizes and prices from a facility's pricing page
  # Returns an array of unit attribute hashes
  def parse_units(page, facility)
    units = []

    begin
      log_info("Loading pricing page for #{facility.name}")

      # Wait for the unit grid to render
      page.wait_for_selector(
        ".unit-grid, [data-testid='unit-list'], .storage-units, .units-container",
        timeout: 15_000
      )

      # Extra Space sometimes has a "Climate Controlled" tab that needs clicking
      # Try clicking it — if it doesn't exist, that's fine, we just continue
      cc_tab = page.query_selector("[data-filter='climate-controlled'], button[data-unit-type='climate']")
      # Note: We do NOT click this — we want ALL unit types and filter ourselves
      # This just tells us the tab exists (useful for debugging if needed)

      # Find all unit rows/cards on the page
      unit_elements = page.query_selector_all(
        "[data-testid='unit-card'], .unit-row, .unit-item, .storage-unit-card"
      )

      if unit_elements.empty?
        log_warning(
          "No unit elements found on #{facility.name}'s pricing page. " \
          "Selectors tried: '[data-testid=unit-card]', '.unit-row', '.unit-item', '.storage-unit-card'. " \
          "The page may have rendered differently than expected. " \
          "Run ReconService on this URL to get current selectors: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      log_info("Found #{unit_elements.length} unit elements on page — parsing each")

      unit_elements.each_with_index do |el, index|
        begin
          # Size: usually something like "10' × 10'" or "10x10"
          raw_size = safe_text(el, "[data-testid='unit-size'], .unit-size, .size-label, h3, h4")
          size     = parse_size(raw_size)

          if size.blank?
            log_warning("Could not determine size for unit ##{index + 1} at #{facility.name} — skipping")
            next
          end

          # Street rate (regular walk-in price)
          street_rate_text = safe_text(el, "[data-testid='street-rate'], .street-rate, .regular-price")
          monthly_price    = parse_price(street_rate_text)

          # Web rate (online promotional price — lower than street rate)
          web_rate_text     = safe_text(el, "[data-testid='web-rate'], .web-rate, .online-price, .special-price")
          web_special_price = parse_price(web_rate_text)

          # Web special note (e.g. "First month free" or "Online only")
          web_special_note = safe_text(el, "[data-testid='promotion-text'], .promo-text, .special-note")

          # Is this unit climate controlled?
          # Extra Space uses data attributes OR text labels for this
          cc_attr = el.get_attribute("data-climate-controlled") ||
                    el.get_attribute("data-feature-climate")
          cc_text = safe_text(el, ".feature-tag, .unit-feature, [data-testid='features']")
          climate_controlled = cc_attr == "true" ||
                               cc_text.to_s.downcase.include?("climate") ||
                               cc_text.to_s.downcase.include?("temperature")

          # Is the unit available?
          # Extra Space marks unavailable units with a class or data attribute
          unavailable = el.get_attribute("data-available") == "false" ||
                        el.query_selector(".sold-out, .unavailable, [data-status='unavailable']").present?
          available = !unavailable

          # Unit type — try to detect locker, parking, etc. from text
          features_text = safe_text(el, ".features-list, .unit-features, .amenities") || ""
          unit_type     = detect_unit_type(features_text, size)

          # Is this a drive-up unit?
          drive_up = features_text.downcase.include?("drive-up") ||
                     features_text.downcase.include?("drive up") ||
                     features_text.downcase.include?("outdoor")

          # Is it indoor?
          indoor = !drive_up && unit_type != "outdoor"

          # The booking link for this specific unit
          booking_link = safe_attr(el, "a[href*='reserve'], a[href*='book'], a.reserve-button", "href")
          booking_url  = booking_link ? "#{BASE_URL}#{booking_link}" : facility.facility_url

          # Admin fee (sometimes shown per-unit, sometimes facility-wide)
          admin_fee_text = safe_text(el, ".admin-fee, [data-testid='admin-fee']")
          admin_fee      = parse_price(admin_fee_text)

          # Insurance note (Extra Space often requires it)
          insurance_note = safe_text(el, ".insurance-note, .insurance-required, [data-testid='insurance']")

          units << {
            size:              size,
            monthly_price:     monthly_price,
            web_special_price: web_special_price,
            web_special_note:  web_special_note,
            admin_fee:         admin_fee,
            insurance_note:    insurance_note,
            climate_controlled: climate_controlled,
            available:         available,
            drive_up:          drive_up,
            indoor:            indoor,
            unit_type:         unit_type,
            booking_url:       booking_url
          }

        rescue => e
          log_warning("Error parsing unit ##{index + 1} at #{facility.name}: #{e.class}: #{e.message}")
          # Keep going — don't let one bad unit kill the rest
        end
      end

    rescue Playwright::TimeoutError => e
      log_error(
        "Timed out waiting for unit list at #{facility.name}. " \
        "URL: #{facility.facility_url}. Error: #{e.message}"
      )
      take_error_screenshot(page, "units_timeout_#{facility.id}")

    rescue => e
      log_error(
        "Unexpected error parsing units at #{facility.name}: #{e.class}: #{e.message}. " \
        "Backtrace: #{e.backtrace.first(5).join(" | ")}"
      )
      take_error_screenshot(page, "units_error_#{facility.id}")
    end

    units
  end

  # ---------------------------------------------------------------------------
  # PRIVATE HELPERS
  # ---------------------------------------------------------------------------
  private

  # Try to extract a numeric facility ID from a URL
  # Extra Space URLs often look like: /storage/find-storage/in/gilbert-az/1234567/
  def extract_id_from_url(url)
    return nil if url.blank?

    # Look for a sequence of 6+ digits in the URL path
    match = url.match(/\/(\d{6,})/)
    match ? match[1] : nil
  end

  # Detect what type of unit this is based on its features text and size
  # Returns a unit_type string that matches our EXCLUDED_TYPES list
  def detect_unit_type(features_text, size)
    text = features_text.to_s.downcase

    return "parking"    if text.include?("parking")
    return "rv"         if text.include?("rv") || text.include?("recreational vehicle")
    return "boat"       if text.include?("boat")
    return "locker"     if text.include?("locker")
    return "mailbox"    if text.include?("mailbox") || text.include?("mail box")
    return "vehicle"    if text.include?("vehicle storage") || text.include?("car storage")
    return "motorcycle" if text.include?("motorcycle")
    return "outdoor"    if text.include?("outdoor") || text.include?("outside")

    # If none of the exclusion keywords match, it's a standard unit
    "standard"
  end
end
