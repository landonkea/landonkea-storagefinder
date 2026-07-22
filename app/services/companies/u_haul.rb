# =============================================================================
# U-HAUL SELF-STORAGE PARSER
# =============================================================================
# Crawls uhaul.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site — see recon/ for
# saved HTML/screenshots, and /tmp/uhaul_* scratch files used during
# development):
#   - There is no lat/lng or radius query-param search endpoint (the stub's
#     guess of ?lat=&lng=&radius= 404s — see recon/uhaul_*_screenshot.png).
#     The real search box (#movingFromInput on https://www.uhaul.com/Storage/)
#     takes free-text "City, State", and on submit redirects the browser to a
#     path-based URL: /Storage/<City>-<State>/Results/ (spaces in the city
#     name become hyphens, e.g. "San Tan Valley, AZ" -> "San-Tan-Valley-AZ").
#     That path also works when navigated to directly, so we reverse-geocode
#     the lat/lng we're given (Geocoder gem) into city/state and build the
#     URL ourselves, same pattern as Companies::PublicStorage.
#   - The results page has no radius filter/param — it just lists facilities
#     sorted by distance from the searched city (with "Nearby Cities" links
#     if the immediate area is sparse). We don't attempt to enforce
#     radius_miles client-side; the same limitation applies to the working
#     Public Storage parser.
#   - Facility cards render server-side in #storageResults > li.divider —
#     unlike some other sites there's no hidden "no results" element to trip
#     over; an empty city legitimately renders zero <li> cards.
#   - Each facility card's name link (h3 a) is also the URL to that
#     facility's own detail page, and that detail page (not the search
#     results page) is where per-unit sizes/prices actually live, grouped
#     into <ul class="uhjs-unit-list"> blocks whose id encodes the room
#     category, e.g. "small_IndoorStorage_RoomList" or
#     "medium_DriveUpStorage_RoomList". So parse_units re-navigates (via the
#     base class's normal per-location page visit) to that same detail URL
#     that parse_locations discovered — no special-casing needed in
#     BaseParser#run.
#   - No bot-detection / CAPTCHA / "press and hold" challenge was encountered
#     at any point (search page, results page, or facility detail pages) —
#     real facility and unit data rendered directly in the HTML every time.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.uhaul.com/Storage/Gilbert-AZ/Results/')"
# =============================================================================

class Companies::UHaul < Companies::BaseParser
  BASE_URL = "https://www.uhaul.com"

  def company_name
    "U-Haul Self-Storage"
  end

  def company_slug
    "uhaul"
  end

  def search_url(lat, lng, radius_miles)
    city, state = reverse_geocode_city_state(lat, lng)
    slug = "#{city}-#{state}".gsub(/\s+/, "-")
    "#{BASE_URL}/Storage/#{ERB::Util.url_encode(slug)}/Results/"
  end

  def parse_locations(page)
    locations = []

    begin
      page.wait_for_selector("#storageResults li.divider", timeout: 15_000) rescue nil

      cards = page.query_selector_all("#storageResults li.divider")

      if cards.empty?
        log_warning(
          "No facility cards found on U-Haul search results page " \
          "(selector: '#storageResults li.divider'). This may mean the searched " \
          "city/state genuinely has no nearby U-Haul locations, or the page " \
          "layout changed — run ReconService to check."
        )
        take_error_screenshot(page, "no_cards")
        return []
      end

      log_info("Found #{cards.length} U-Haul locations")

      cards.each_with_index do |card, idx|
        begin
          name_link = card.query_selector("h3 a")
          name      = name_link&.text_content&.strip
          url       = name_link&.get_attribute("href")&.strip

          next if name.blank? || url.blank?

          external_id = url[/\/(\d+)\/?\z/, 1]

          address_raw = safe_attr(card, "a.address-link", "rel")

          street = nil
          city   = nil
          state  = nil
          zip    = nil

          if address_raw.present?
            # Format: "2557 S Gilbert Rd  Gilbert,AZ 85295" — street and
            # "City,State Zip" are separated by 2+ spaces, city/state by a
            # comma with no space.
            street_part, city_state_zip = address_raw.split(/\s{2,}/, 2)
            street = street_part&.strip

            if city_state_zip.present?
              city_part, state_zip = city_state_zip.split(",", 2)
              city = city_part&.strip

              if state_zip.present?
                state_zip_parts = state_zip.strip.split(/\s+/)
                state = state_zip_parts[0]
                zip   = state_zip_parts[1]
              end
            end
          end

          next if street.blank?

          locations << {
            name:        name,
            address:     street,
            city:        city || "",
            state:       state || "AZ",
            zip:         zip || "",
            phone:       nil,
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{name} — #{street}, #{city}, #{state}")

        rescue => e
          log_warning("Error parsing U-Haul card ##{idx + 1}: #{e.class}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for U-Haul search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing U-Haul locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  def parse_units(page, facility)
    units = []

    begin
      page.wait_for_selector("ul.uhjs-unit-list", timeout: 15_000)

      room_lists = page.query_selector_all("ul.uhjs-unit-list")

      if room_lists.empty?
        log_warning(
          "No unit room lists found at #{facility.name}. Selector: 'ul.uhjs-unit-list'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      # The facility-wide "no admin fee" callout applies to every unit on the
      # page (U-Haul doesn't show a per-unit admin fee) — grab it once.
      admin_fee = page.content.include?("$0.00 Admin Fee") ? 0.0 : nil

      idx = 0

      room_lists.each do |room_list|
        list_id    = room_list.get_attribute("id").to_s.downcase
        drive_up   = list_id.include?("driveup")
        vehicleish = list_id.match?(/vehicle|rv|boat|parking|outdoor/)
        indoor     = list_id.include?("indoor")

        unit_type =
          if vehicleish
            if list_id.include?("boat") then "boat"
            elsif list_id.include?("rv") then "rv"
            elsif list_id.include?("parking") then "parking"
            elsif list_id.include?("vehicle") then "vehicle"
            else "outdoor"
            end
          else
            "standard"
          end

        room_list.query_selector_all("li").each do |el|
          idx += 1

          begin
            raw_size = safe_text(el, "h4 span.nowrap") || safe_text(el, "h4")
            size     = parse_size(raw_size)
            next if size.blank?

            price_texts   = safe_all_text(el, "dd b")
            monthly_price = price_texts.map { |t| parse_price(t) }.compact.first

            features = safe_all_text(el, "ul.collapse.condensed li").map(&:downcase)
            climate_controlled = features.any? { |f| f.include?("climate") }

            units << {
              size:               size,
              monthly_price:      monthly_price,
              web_special_price:  nil,
              web_special_note:   nil,
              admin_fee:          admin_fee,
              insurance_note:     nil,
              climate_controlled: climate_controlled,
              available:          true,
              drive_up:           drive_up,
              indoor:             indoor && !drive_up,
              unit_type:          unit_type,
              booking_url:        facility.facility_url
            }

          rescue => e
            log_warning("Error parsing unit ##{idx} at #{facility.name}: #{e.message}")
          end
        end
      end

      if units.empty?
        log_warning(
          "Unit room lists were present but no individual units parsed at " \
          "#{facility.name}. Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
      else
        log_info("Found #{units.length} units at #{facility.name}")
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

  # U-Haul's search box takes a free-text "City, State" query, not
  # coordinates — reverse-geocode what we were given back into that form.
  # The URL also works fine with the full state name (e.g. "Gilbert-Arizona")
  # but we prefer the 2-letter abbreviation when Nominatim's ISO code is
  # available, to match what the site's own search box produces.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    if result&.city.present?
      iso = result.data.dig("address", "ISO3166-2-lvl4")
      state_abbr = iso&.split("-")&.last || result.state
      [ result.city, state_abbr ]
    else
      [ lat.to_s, lng.to_s ]
    end
  rescue => e
    log_warning("Reverse geocoding failed for #{lat},#{lng}: #{e.message}")
    [ lat.to_s, lng.to_s ]
  end
end
