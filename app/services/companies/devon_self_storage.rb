# =============================================================================
# DEVON SELF STORAGE PARSER
# =============================================================================
# Crawls devonselfstorage.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site — see recon/ for
# saved HTML/screenshots, and ad-hoc scratch scripts used during development):
#   - /locations/ (the stub's guess) 404s. The real search box lives on the
#     homepage (#markets-autocomplete-input, form action="/search") and takes
#     free-text "City, State". Selecting an autocomplete suggestion renders
#     results as an in-page overlay WITHOUT changing window.location (a
#     Next.js intercepted route) — but critically, navigating directly to
#     "/search?q=<City>%2C+<ST>" (no interactive typing needed) renders the
#     exact same results server-side. We reverse-geocode the lat/lng we're
#     given into "City, ST" (Geocoder gem) and build that URL ourselves, same
#     pattern as Companies::PublicStorage / Companies::UHaul.
#   - The search results page has no radius query param — it just lists the
#     nearest facilities to the searched city. We don't attempt to enforce
#     radius_miles client-side; the same limitation applies to the working
#     Public Storage / U-Haul parsers.
#   - Facility cards render server-side as `article.facility-card` (inside
#     `section.facility-grid`). Each card carries rich data attributes
#     (data-title, data-lat, data-lng, data-features) and TWO duplicate
#     `address.address` blocks (one for the map info-window, one for the
#     list row) — must scope to the FIRST `address.address` per card, not
#     `query_selector_all("address.address span")` on the whole card, or the
#     street/city-state-zip lines from both blocks interleave.
#   - Each facility's own detail page (linked via `a[href^="/storage-locations/"]`,
#     both the "Visit Location" and "Available Units" buttons point to the
#     same URL) renders unit pricing server-side as `div.unit-item` blocks —
#     dimension, category, feature list, promo text, and price are all
#     present without any extra API call.
#   - Per-unit price is a single "Starting at $X.XX" value (`.unit-item-price__web-rate`)
#     — there's no separate strikethrough/list price in the markup, so we
#     treat any promo text (e.g. "First Month FREE", "Half Month FREE") as
#     web_special_note rather than a numeric web_special_price.
#   - `data-features` on each unit-item is a comma-separated list, e.g.
#     "climate-control,ground-level,inside" or "outside-drive-up-unit" or
#     "outside-drive-up-unit,covered-parking". climate_controlled/drive_up/
#     indoor are all derived from this list.
#   - Parking spaces (`data-categories="parking"`) only have a single
#     dimension (e.g. "26'"), so parse_size (which requires two numbers)
#     naturally drops them — consistent with how they'd be filtered out
#     downstream anyway (apply_filters excludes drive_up/non-indoor units).
#   - No bot-detection / CAPTCHA / "press and hold" challenge was encountered
#     at any point (homepage, direct /search?q= navigation, or facility
#     detail pages) — real facility and unit data rendered directly in the
#     HTML every time.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.devonselfstorage.com/search?q=Gilbert%2C+AZ')"
# =============================================================================

class Companies::DevonSelfStorage < Companies::BaseParser
  BASE_URL = "https://www.devonselfstorage.com"

  def company_name
    "Devon Self Storage"
  end

  def company_slug
    "devon_self_storage"
  end

  def search_url(lat, lng, radius_miles)
    location_query = reverse_geocode_city_state(lat, lng)
    "#{BASE_URL}/search?q=#{ERB::Util.url_encode(location_query)}"
  end

  def parse_locations(page)
    locations = []

    begin
      page.wait_for_selector("article.facility-card", timeout: 15_000) rescue nil

      cards = page.query_selector_all("article.facility-card")

      if cards.empty?
        log_warning(
          "No facility cards found on Devon Self Storage search page " \
          "(selector: 'article.facility-card'). This may mean the searched " \
          "city/state genuinely has no nearby Devon locations, or the page " \
          "layout changed — run ReconService to check."
        )
        take_error_screenshot(page, "no_cards")
        return []
      end

      log_info("Found #{cards.length} Devon Self Storage locations")

      cards.each_with_index do |card, idx|
        begin
          name = card.get_attribute("data-title")&.strip

          link    = card.query_selector("a[href^='/storage-locations/']")
          rel_url = link&.get_attribute("href")
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil

          # Each card has TWO duplicate address.address blocks (map
          # info-window + list row) — scope to the first one only, or the
          # street/city-state-zip lines from both blocks interleave.
          first_address = card.query_selector("address.address")
          address_lines = first_address ? safe_all_text(first_address, "span") : []

          street              = address_lines[0]
          city_part, state_zip = address_lines[1].to_s.split(",", 2)
          city                = city_part&.strip
          state_zip_parts     = state_zip.to_s.strip.split(/\s+/)
          state               = state_zip_parts[0]
          zip                 = state_zip_parts[1]

          phone = safe_text(card, ".phone")

          external_id = card.get_attribute("id").to_s[/facility-card-(\d+)/, 1]

          next if street.blank?

          locations << {
            name:        name.presence || "Devon Self Storage - #{street}",
            address:     street,
            city:        city || "",
            state:       state || "AZ",
            zip:         zip || "",
            phone:       phone,
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street} — #{city}, #{state}")

        rescue => e
          log_warning("Error parsing Devon Self Storage card ##{idx + 1}: #{e.class}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for Devon Self Storage search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing Devon Self Storage locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  def parse_units(page, facility)
    units = []

    begin
      page.wait_for_selector("div.unit-item", timeout: 15_000)

      unit_els = page.query_selector_all("div.unit-item")

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: 'div.unit-item'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".unit-item__dimension")
          size     = parse_size(raw_size)
          next if size.blank?

          price_text    = safe_text(el, ".unit-item-price__web-rate")
          monthly_price = parse_price(price_text)
          next if monthly_price.blank?

          features = el.get_attribute("data-features").to_s.split(",").map(&:strip)
          category = el.get_attribute("data-categories").to_s.strip.downcase

          climate_controlled = features.include?("climate-control")
          drive_up           = features.any? { |f| f.include?("drive-up") }
          indoor             = features.include?("inside") && !drive_up

          # No separate strikethrough price in the markup — promo text like
          # "First Month FREE" / "Half Month FREE" is a value-add note, not
          # a numeric discount, so it becomes web_special_note only.
          web_special_note = safe_text(el, ".unit-item__promotions")

          unit_type = category == "parking" ? "parking" : "standard"

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  nil,
            web_special_note:   web_special_note,
            admin_fee:          nil,
            insurance_note:     nil,
            climate_controlled: climate_controlled,
            available:          true,
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

  # Devon's search box takes a free-text "City, State" query, not
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
