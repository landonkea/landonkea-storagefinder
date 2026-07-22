# =============================================================================
# ISTORAGE PARSER
# =============================================================================
# Crawls to find iStorage facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site with Playwright —
# see recon/ for a saved screenshot/report, and the exploration notes below):
#
#   - istorage.com is NOT an independent site anymore. Every single path on
#     istorage.com (including the recon URL istorage.com/storage-units/az/)
#     performs a full redirect to the equivalent nsastorage.com URL. The
#     homepage itself renders as "NSA Storage" branding and explicitly shows
#     an "NSA Storage Family of Brands" carousel (SecurCare, Northwest Self
#     Storage, RightSpace Storage, Move It Storage, Southern Self Storage,
#     iStorage, ...). This is normal corporate site consolidation, not bot
#     detection — no CAPTCHA/"press & hold"/challenge page was ever shown.
#   - The site's own header/search-page search form
#     (id="headerSearchForm" / id="searchForm") POSTs via GET to
#     `https://www.nsastorage.com/search-results?location=<City, State>`,
#     which itself redirects to a friendly URL like
#     `/storage/<state>/storage-units-<city>`. We drive that endpoint
#     directly with a reverse-geocoded "City, State" string (same technique
#     as Companies::PublicStorage — there's no lat/lng search endpoint).
#   - IMPORTANT: nsastorage.com's search-results page returns the nearest
#     facilities from ALL NSA brands mixed together, sorted by distance —
#     not just iStorage. Each result card has a brand-qualified title
#     (e.g. "RightSpace Storage | N Gilbert Rd" or "iStorage | W Davis St").
#     We MUST filter to only cards whose title starts with "iStorage",
#     otherwise we'd be saving RightSpace/SecurCare/etc. facilities under the
#     iStorage company name. In some markets (e.g. Phoenix/Gilbert, AZ — that
#     market is served entirely by RightSpace Storage) this filter will
#     legitimately produce zero iStorage results; that's correct, not a bug.
#   - Facility cards live under `.facility-card` (search-results page). Each
#     has: `h3.part_title_1` (brand-qualified title), `a.part_title_1[href]`
#     (facility detail URL, whose trailing "-<digits>" is the NSA facility
#     ID), `address` (single-line "street, city, ST zip"), and
#     `a[href^="tel:"]` (phone).
#   - Facility detail pages render unit cards under `.unit-select-item`
#     (no separate JSON API call needed). Each has:
#       `.unit-select-item-detail-heading` → size, e.g. "10 x 10"
#       `[data-unit-size]` on the item itself → "small"/"medium"/"large"/"vehicle"
#       `.part_item_price` → current listed price, e.g. "$59/mo"
#       `.part_item_old_price` → higher "In-Store" price when the listed
#         price is an online-only promo (crossed out in the UI)
#       `.part_badge span` → promo badges, e.g. "1st Month Free"
#       `.det-listing li span` → feature tags, e.g. "Drive Up Access",
#         "Outside", "Inside", "1st Floor", "Heated and Cooled"
#       `a.form-opener[href]` → relative booking/reservation URL
#   - `.no-results-description` is present in the DOM on every page load
#     (it's a "no results" fallback for an unrelated unit-filter widget, not
#     the facility search) — like Public Storage's `.no-stores-results-content`
#     trap, its presence can't be used as a signal. We rely on actual counts
#     of `.facility-card` / `.unit-select-item` instead.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.nsastorage.com/storage')"
# =============================================================================

class Companies::IStorage < Companies::BaseParser
  BASE_URL = "https://www.nsastorage.com"

  def company_name
    "iStorage"
  end

  def company_slug
    "istorage"
  end

  def search_url(lat, lng, radius_miles)
    location_query = reverse_geocode_city_state(lat, lng)
    "#{BASE_URL}/search-results?location=#{ERB::Util.url_encode(location_query)}"
  end

  def parse_locations(page)
    locations = []

    begin
      page.wait_for_selector(".facility-card", timeout: 15_000) rescue nil

      all_cards = page.query_selector_all(".facility-card")

      if all_cards.empty?
        log_warning(
          "No facility cards found at all on the NSA Storage search page (selector: '.facility-card'). " \
          "The page layout may have changed. Run ReconService to check current page structure."
        )
        take_error_screenshot(page, "no_cards")
        return []
      end

      # nsastorage.com mixes results from every NSA brand (RightSpace,
      # SecurCare, Northwest, Move It, iStorage, ...) sorted by distance —
      # keep only the ones actually branded "iStorage".
      cards = all_cards.select do |card|
        title = safe_text(card, "h3.part_title_1")
        title.present? && title.strip.start_with?("iStorage")
      end

      if cards.empty?
        log_warning(
          "Found #{all_cards.length} nearby facility card(s), but none were branded 'iStorage' " \
          "(other NSA Storage brands serve this market). Treating as no iStorage locations in range."
        )
        return []
      end

      log_info("Found #{cards.length} iStorage location(s) (out of #{all_cards.length} nearby NSA facilities)")

      cards.each_with_index do |card, idx|
        begin
          link = card.query_selector("a.part_title_1")
          url  = link&.get_attribute("href")

          external_id = url.to_s[/-(\d+)\z/, 1]

          address_line = safe_text(card, "address")
          address_parts = address_line.to_s.split(",").map(&:strip).reject(&:blank?)
          street    = address_parts[0]
          city      = address_parts[1]
          state_zip = address_parts[2].to_s.split(/\s+/)
          state     = state_zip[0]
          zip       = state_zip[1]

          phone = extract_phone(card)

          next if street.blank?

          locations << {
            name:        "iStorage - #{street}",
            address:     street,
            city:        city || "",
            state:       state || "",
            zip:         zip || "",
            phone:       phone,
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street} — #{city}, #{state}")

        rescue => e
          log_warning("Error parsing iStorage card ##{idx + 1}: #{e.class}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for NSA Storage search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing iStorage locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  def parse_units(page, facility)
    units = []

    begin
      page.wait_for_selector(".unit-select-item", timeout: 15_000)

      unit_els = page.query_selector_all(".unit-select-item")

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.unit-select-item'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".unit-select-item-detail-heading")
          size     = parse_size(raw_size)
          next if size.blank?

          current_price = parse_price(safe_text(el, ".part_item_price"))
          old_price     = parse_price(safe_text(el, ".part_item_old_price"))

          badges = safe_all_text(el, ".part_badge span")

          monthly_price     = current_price
          web_special_price = nil
          web_special_note  = nil

          if old_price.present? && current_price.present? && old_price > current_price
            monthly_price     = old_price
            web_special_price = current_price
            web_special_note  = badges.present? ? "Online price — #{badges.join(', ')}" : "Online price"
          elsif badges.present?
            web_special_note = badges.join(", ")
          end

          next if monthly_price.blank?

          features = safe_all_text(el, ".det-listing li span")
          feature_text = features.join(" | ").downcase

          climate_controlled = feature_text.include?("heated and cooled") || feature_text.include?("climate")
          drive_up            = feature_text.include?("drive up")
          indoor               = feature_text.include?("inside") || (!drive_up && feature_text.include?("floor"))
          indoor               = !drive_up if features.empty?

          data_unit_size = el.get_attribute("data-unit-size").to_s
          unit_type = data_unit_size == "vehicle" ? "vehicle" : "standard"

          relative_booking_url = safe_attr(el, "a.form-opener", "href")
          booking_url = relative_booking_url.present? ? "#{BASE_URL}#{relative_booking_url}" : facility.facility_url

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

  # iStorage's (nsastorage.com's) search box takes a free-text "City, State"
  # query, not coordinates — reverse-geocode what we were given back into
  # that form. Same approach as Companies::PublicStorage.
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

  # The phone link's text_content includes a leading sr-only "Call to speak
  # with a Storage Specialist at " label glued onto the number, so we read
  # the tel: href instead and format it.
  def extract_phone(card)
    href = safe_attr(card, "a[href^='tel:']", "href")
    return nil if href.blank?

    digits = href.sub(/\Atel:/, "").gsub(/\D/, "")
    return nil if digits.length != 10

    "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}"
  end
end
