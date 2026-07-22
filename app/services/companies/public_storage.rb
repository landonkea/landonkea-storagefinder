# =============================================================================
# PUBLIC STORAGE PARSER
# =============================================================================
# Crawls publicstorage.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site — see recon/ for
# saved HTML/screenshots):
#   - There is no lat/lng search endpoint. The search page takes a free-text
#     `location` query param: /self-storage-search?location=<City, State>.
#     We reverse-geocode the lat/lng we're given into a city/state via the
#     Geocoder gem (already configured for forward geocoding elsewhere).
#   - Search results AND facility detail pages both render facility/unit data
#     server-side under `.store-container` / `.unit-list-item` — no separate
#     JSON API call needed.
#   - "$1 first month" / "Online price" deals are common — captured as
#     web_special_price.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.publicstorage.com/self-storage-search?location=Gilbert%2C+Arizona')"
# =============================================================================

class Companies::PublicStorage < Companies::BaseParser
  BASE_URL = "https://www.publicstorage.com"

  def company_name
    "Public Storage"
  end

  def company_slug
    "public_storage"
  end

  def search_url(lat, lng, radius_miles)
    location_query = reverse_geocode_city_state(lat, lng)
    "#{BASE_URL}/self-storage-search?location=#{ERB::Util.url_encode(location_query)}"
  end

  def parse_locations(page)
    locations = []

    begin
      # NOTE: .no-stores-results-content is present in the DOM on every page
      # load (just hidden via CSS when there are results), so it can't be
      # used as a presence check — .store-container count is the real signal.
      page.wait_for_selector(".store-container", timeout: 15_000) rescue nil

      cards = page.query_selector_all(".store-container")

      if cards.empty?
        log_warning(
          "No facility cards found on Public Storage search page (selector: '.store-container'). " \
          "Run ReconService to check current page structure."
        )
        take_error_screenshot(page, "no_cards")
        return []
      end

      log_info("Found #{cards.length} Public Storage locations")

      cards.each_with_index do |card, idx|
        begin
          link    = card.query_selector("a.plp-link")
          rel_url = link&.get_attribute("href")
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil

          address_lines = safe_text(card, ".store-address")&.split(",")&.map(&:strip)&.reject(&:blank?) || []
          street        = address_lines[0]
          city          = address_lines[1]
          # Last line is "AZ 85296" (state + zip together)
          state_zip     = address_lines[2].to_s.split(/\s+/)
          state         = state_zip[0]
          zip           = state_zip[1]

          external_id = card.get_attribute("data-storeid")

          next if street.blank?

          locations << {
            name:        "Public Storage - #{street}",
            address:     street,
            city:        city || "",
            state:       state || "AZ",
            zip:         zip || "",
            phone:       nil,
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street} — #{city}, #{state}")

        rescue => e
          log_warning("Error parsing Public Storage card ##{idx + 1}: #{e.class}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for Public Storage search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing Public Storage locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  def parse_units(page, facility)
    units = []

    begin
      page.wait_for_selector(".unit-list-item", timeout: 15_000)

      unit_els = page.query_selector_all(".unit-list-item")

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.unit-list-item'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".size")
          size     = parse_size(raw_size)
          next if size.blank?

          # The real numeric price lives in a data attribute — more reliable
          # than parsing the "$26" text nodes.
          price_el      = el.query_selector(".unit-price[data-pricebook-price]")
          monthly_price = price_el&.get_attribute("data-pricebook-price")&.to_f
          monthly_price = nil if monthly_price.blank? || monthly_price <= 0

          list_price = price_el&.get_attribute("data-list-price")&.to_f
          web_special_price = nil
          web_special_note  = nil
          if list_price.present? && list_price > 0 && monthly_price.present? && list_price > monthly_price
            web_special_price = monthly_price
            web_special_note  = "Online price"
            monthly_price     = list_price
          end

          classes             = el.get_attribute("class").to_s
          climate_controlled  = classes.include?("ClimateControl")
          drive_up            = classes.include?("IsDriveUpAccess")
          indoor              = !drive_up
          is_vehicle          = classes.include?("IsVehicleUnit")

          sold_out  = el.query_selector(".sold-out, .unavailable") ? true : false
          available = !sold_out

          unit_type = is_vehicle ? "vehicle" : "standard"

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price,
            web_special_note:   web_special_note,
            climate_controlled: climate_controlled,
            available:          available,
            drive_up:           drive_up,
            indoor:             indoor,
            unit_type:          unit_type,
            booking_url:        facility.facility_url
          }

        rescue => e
          log_warning("Error parsing unit ##{idx + 1} at #{facility.name}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for units at #{facility.name}: #{e.message}")
      take_error_screenshot(page, "units_timeout_#{facility.id}")
    rescue => e
      log_error("Error parsing units at #{facility.name}: #{e.class}: #{e.message}")
      take_error_screenshot(page, "units_error_#{facility.id}")
    end

    units
  end

  private

  # Public Storage's search box takes a free-text "City, State" query, not
  # coordinates — reverse-geocode what we were given back into that form.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    if result&.city.present?
      "#{result.city}, #{result.state}"
    else
      "#{lat},#{lng}"
    end
  rescue => e
    log_warning("Reverse geocoding failed for #{lat},#{lng}: #{e.message}")
    "#{lat},#{lng}"
  end
end
