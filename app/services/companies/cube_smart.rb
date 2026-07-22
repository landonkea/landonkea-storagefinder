# =============================================================================
# CUBESMART PARSER
# =============================================================================
# Crawls cubesmart.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site with Playwright —
# no bot-detection/CAPTCHA was ever encountered on normal search/facility
# pages; see recon/ + investigation notes below):
#   - There is no lat/lng search endpoint. The homepage search box is a JS
#     autocomplete that, on submit, redirects the browser to one of:
#       https://www.cubesmart.com/<zip>-self-storage/
#       https://www.cubesmart.com/<state-slug>-self-storage/<city-slug>-self-storage/
#     Both URL forms work fine when navigated to directly (no need to drive
#     the search box with Playwright) — we build the zip form directly from
#     reverse-geocoding the given lat/lng (falls back to the city/state slug
#     form if geocoding doesn't return a postal code).
#   - The search results page renders ALL nearby facilities (30+) into the DOM
#     server-side under `.csStorageListing` — the "1 2 3" pager visible in the
#     UI is a client-side JS view over data that's already fully present, so
#     there's no need to click through pages. Each card's address anchor
#     (`a[id$='-see-all-address']`) carries `facility="<id>"` (matches the
#     `<id>.html` in its href) and `distance="<miles>"` attributes — used for
#     the external_id and for filtering to the requested radius.
#   - Facility detail pages (the linked `.html` page) render the FULL unit
#     list server-side under `.csUnitFacilityListing` — no "See Units" click
#     needed. Each unit row carries `data-tab-group` (Small/Medium/Large/
#     Parking), a friendly size description (e.g. "10'x10'* Storage Unit"),
#     a list of feature `<li>` tags (Climate Controlled, Indoor Storage Unit,
#     Outside Drive-Up Access, Heated / Air Cooled, Covered Parking, ...),
#     an original ("in store") strike-through price and a discounted
#     ("online") price.
#   - One trap encountered: guessing a nonsense URL (duplicate city/state
#     segment, or a made-up facility id under the wrong city slug) can return
#     a `403 Forbidden` served by an Incapsula-fronted WAF. This only showed
#     up for made-up/malformed URLs, never for a real search or a real
#     facility link discovered from a search results page — it reads as a
#     WAF rule against malformed paths, not an interactive human-verification
#     challenge (no CAPTCHA/press-and-hold/verify-you're-human page was ever
#     shown). We treat a 403 / empty result the same as "no results" and move
#     on rather than trying to work around it.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.cubesmart.com/85296-self-storage/')"
# =============================================================================

class Companies::CubeSmart < Companies::BaseParser
  BASE_URL = "https://www.cubesmart.com"

  def company_name
    "CubeSmart"
  end

  def company_slug
    "cubesmart"
  end

  def search_url(lat, lng, radius_miles)
    # Stashed so parse_locations can filter results to the requested radius —
    # the search results page itself doesn't take a radius param, it just
    # returns whatever it considers "nearby" (seen up to ~20mi in testing).
    @radius_miles = radius_miles

    zip = reverse_geocode_zip(lat, lng)
    if zip.present?
      "#{BASE_URL}/#{zip}-self-storage/"
    else
      location = reverse_geocode_city_state(lat, lng)
      if location
        "#{BASE_URL}/#{location[:state].parameterize}-self-storage/#{location[:city].parameterize}-self-storage/"
      else
        # Last-ditch fallback — unlikely to resolve, but keeps search_url
        # from raising if geocoding totally failed.
        "#{BASE_URL}/#{lat},#{lng}-self-storage/"
      end
    end
  end

  def parse_locations(page)
    locations = []

    begin
      # NOTE: the visible "1 2 3" pager is purely client-side — every card is
      # already present in the DOM on first load, so .csStorageListing count
      # is a reliable "did we get real results" signal (unlike sites where a
      # hidden "no results" div is always present).
      page.wait_for_selector(".csStorageListing", timeout: 15_000) rescue nil

      cards = page.query_selector_all(".csStorageListing")

      if cards.empty?
        log_warning(
          "No facility cards found on CubeSmart search page (selector: '.csStorageListing'). " \
          "Run ReconService to check current page structure, or the search location may have " \
          "resolved to a 403/empty results page."
        )
        take_error_screenshot(page, "no_cards")
        return []
      end

      log_info("Found #{cards.length} CubeSmart locations")

      cards.each_with_index do |card, idx|
        begin
          link_el = card.query_selector("a[id$='-see-all-address']")
          rel_url = link_el&.get_attribute("href")
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil

          external_id   = link_el&.get_attribute("facility")
          distance_str  = link_el&.get_attribute("distance")
          distance_mi   = distance_str.presence&.to_f

          # Skip locations outside the requested radius — the site returns
          # whatever it considers "nearby" regardless of what we asked for.
          if @radius_miles.present? && distance_mi.present? && distance_mi > @radius_miles.to_f
            next
          end

          address_lines = card.query_selector_all(".csFacilityLocation h3 span")
                              .map { |s| s.text_content&.strip }
                              .reject(&:blank?)

          street         = address_lines[0]
          city_state_zip = address_lines[1].to_s
          city           = city_state_zip.split(",").first&.strip
          state_zip      = city_state_zip.split(",").last.to_s.strip.split(/\s+/)
          state          = state_zip[0]
          zip            = state_zip[1]

          next if street.blank?

          locations << {
            name:        "CubeSmart - #{street}",
            address:     street,
            city:        city || "",
            state:       state || "",
            zip:         zip || "",
            phone:       nil,
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street} — #{city}, #{state}")

        rescue => e
          log_warning("Error parsing CubeSmart card ##{idx + 1}: #{e.class}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for CubeSmart search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing CubeSmart locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  def parse_units(page, facility)
    units = []

    begin
      page.wait_for_selector(".csUnitFacilityListing", timeout: 15_000)

      # Facility-specific "Current Customers" number — the "New Customers"
      # number is a shared marketing/tracking line, not this store's line.
      phone = safe_text(page, ".csFacilityPhone a.new-phone:not(.new-customer)")
      if phone.blank?
        phone = safe_attr(page, ".csFacilityPhone a[href^='tel:']", "href")&.sub(/^tel:/, "")
      end
      if phone.present? && facility.phone.blank?
        facility.update(phone: phone)
      end

      unit_els = page.query_selector_all(".csUnitFacilityListing")

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.csUnitFacilityListing'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          tab_group = el.get_attribute("data-tab-group").to_s

          raw_size = safe_text(el, ".csUnitColumn01 p span[aria-hidden]")
          size     = parse_size(raw_size)
          next if size.blank?

          discount_text = safe_text(el, ".ptDiscountPriceSpan")
          original_text = safe_text(el, ".ptOriginalPriceSpan")

          discount_price = parse_price(discount_text)
          original_price = parse_price(original_text)

          monthly_price      = nil
          web_special_price  = nil
          web_special_note   = nil

          if original_price.present? && discount_price.present? && original_price > discount_price
            monthly_price     = original_price
            web_special_price = discount_price
            web_special_note  = "Online price"
          else
            monthly_price = discount_price || original_price
          end

          next if monthly_price.blank?

          features = el.query_selector_all(".csDisplayFeatures li").map { |li| li.text_content&.strip }.compact

          is_parking          = tab_group.casecmp?("parking")
          drive_up            = features.any? { |f| f =~ /drive-up/i }
          climate_controlled  = features.any? { |f| f =~ /climate|heated|air cooled/i }
          indoor              = !is_parking && !drive_up

          unit_type = is_parking ? "parking" : "standard"

          reserve_path = safe_attr(el, "a.red-button", "href")
          booking_url  = reserve_path ? "#{BASE_URL}#{reserve_path}" : facility.facility_url

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price,
            web_special_note:   web_special_note,
            climate_controlled: climate_controlled,
            available:          true,
            drive_up:           drive_up,
            indoor:             indoor,
            unit_type:          unit_type,
            booking_url:        booking_url
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

  # CubeSmart's search box (and its dedicated <zip>-self-storage/ URL) takes
  # a plain US zip code — reverse-geocode what we were given back into one.
  def reverse_geocode_zip(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    result&.postal_code.presence
  rescue => e
    log_warning("Reverse geocoding (zip) failed for #{lat},#{lng}: #{e.message}")
    nil
  end

  # Fallback for the rare case reverse geocoding doesn't yield a zip —
  # CubeSmart's alternate URL form takes a full state name + city name.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    return nil unless result&.city.present? && result&.state.present?

    { city: result.city, state: result.state }
  rescue => e
    log_warning("Reverse geocoding (city/state) failed for #{lat},#{lng}: #{e.message}")
    nil
  end
end
