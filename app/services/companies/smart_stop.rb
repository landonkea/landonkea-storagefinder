# =============================================================================
# SMARTSTOP SELF STORAGE PARSER
# =============================================================================
# Crawls smartstopselfstorage.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site — see recon/ for
# saved HTML/screenshots, and the ad-hoc scripts used to discover this):
#   - No bot-detection/CAPTCHA challenge was ever encountered on this site
#     while doing this research (no Cloudflare/PerimeterX challenge page, no
#     "press & hold" gate — the "Protected by Cloudflare" footer badge is
#     just a static trust badge, not an active challenge).
#   - The search page takes real lat/lng query params directly:
#       /find-storage?latitude=<lat>&longitude=<lng>
#     (Confirmed by driving the on-page location-search box, which is a
#     Google Places Autocomplete widget — selecting/submitting a place
#     navigates the browser to exactly this URL shape.)
#   - The site does NOT expose a radius query param — it always searches a
#     fixed 25-mile radius regardless of what's passed, so `radius_miles`
#     is accepted for interface compatibility but not used.
#   - Search results render server-side as `.location-card` elements, each
#     with a link (`.location-card__buttons a`) to that facility's detail
#     page at /find-storage/<state>/<city>/<slug>?unitSize=all — visiting
#     with `unitSize=all` renders ALL unit cards (all size tabs) at once
#     instead of needing to click through Small/Medium/Large/Vehicle tabs.
#   - Facility detail pages render unit pricing server-side as `.unit-card`
#     elements. Each shows a crossed-out "In-Store" price
#     (`.unit-card__cost__store__value`) and a lower "Promo Rate" price
#     (`.unit-card__cost__web__value`) when a web special applies. Promo
#     badges (`.unit-card__cost__badges__promo .badge`) sometimes include a
#     one-time admin fee breakdown, e.g. "One-Time Admin Fee$29.00".
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.smartstopselfstorage.com/find-storage')"
# =============================================================================

class Companies::SmartStop < Companies::BaseParser
  BASE_URL = "https://www.smartstopselfstorage.com"

  def company_name
    "SmartStop"
  end

  def company_slug
    "smartstop"
  end

  def search_url(lat, lng, radius_miles)
    # SmartStop's search endpoint takes real lat/lng directly — no
    # reverse-geocoding needed. radius_miles is unused: the site has no
    # radius param and always searches a fixed 25-mile radius.
    "#{BASE_URL}/find-storage?latitude=#{lat}&longitude=#{lng}"
  end

  def parse_locations(page)
    locations = []

    begin
      page.wait_for_selector(".location-card", timeout: 15_000) rescue nil

      cards = page.query_selector_all(".location-card")

      if cards.empty?
        log_warning(
          "No facility cards found on SmartStop search page (selector: '.location-card'). " \
          "Run ReconService to check current page structure."
        )
        take_error_screenshot(page, "no_cards")
        return []
      end

      log_info("Found #{cards.length} SmartStop locations")

      cards.each_with_index do |card, idx|
        begin
          link    = card.query_selector(".location-card__buttons a")
          rel_url = link&.get_attribute("href")
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil

          street            = safe_text(card, ".location-card__address1")
          city_state_zip    = safe_text(card, ".location-card__address2")
          city, state, zip  = parse_city_state_zip(city_state_zip)

          next if street.blank?

          # The URL slug (e.g. "/find-storage/az/phoenix/1500-e-baseline-rd")
          # is stable per facility and unique — use it as external_id since
          # the search results page doesn't expose a numeric store ID.
          external_id = rel_url&.split("?")&.first

          locations << {
            name:        "SmartStop Self Storage - #{street}",
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
          log_warning("Error parsing SmartStop card ##{idx + 1}: #{e.class}: #{e.message}")
        end
      end

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for SmartStop search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      log_error("Unexpected error parsing SmartStop locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end

    locations
  end

  def parse_units(page, facility)
    units = []

    begin
      page.wait_for_selector(".unit-card", timeout: 15_000)

      cards = page.query_selector_all(".unit-card")

      if cards.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.unit-card'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end

      log_info("Found #{cards.length} units at #{facility.name}")

      cards.each_with_index do |card, idx|
        begin
          raw_size = safe_text(card, ".unit-card__size__dimension")
          size     = parse_size(raw_size)
          next if size.blank?

          features = safe_all_text(card, ".unit-card__features__list li").map(&:downcase)

          climate_controlled = features.any? { |f| f.include?("climate") }
          drive_up           = features.any? { |f| f.include?("drive-up") }
          outdoor             = features.any? { |f| f.include?("outside") || f.include?("outdoor") }
          indoor              = !outdoor
          is_vehicle          = features.any? { |f| f.include?("vehicle") || f.include?("rv") || f.include?("boat") }
          unit_type           = is_vehicle ? "vehicle" : "standard"

          in_store_price = parse_price(safe_text(card, ".unit-card__cost__store__value"))
          promo_price    = parse_price(safe_text(card, ".unit-card__cost__web__value"))

          # In-store (crossed-out) price is the "regular" price; the lower
          # promo price (when present) is the web special.
          monthly_price      = in_store_price || promo_price
          web_special_price  = nil
          web_special_note   = nil
          admin_fee          = nil

          if promo_price.present? && in_store_price.present? && promo_price < in_store_price
            web_special_price = promo_price

            badge_text = safe_text(card, ".unit-card__cost__badges__promo .badge")
            if badge_text.present?
              # Badge text concatenates the headline with a hidden tooltip's
              # detail rows, e.g. "1st Month Rent Free *Move-In CostsOne-Time
              # Admin Fee$29.00...". Split off just the headline.
              web_special_note = badge_text.split(/Move-In Costs/i).first.to_s.strip.presence

              if (m = badge_text.match(/Admin Fee\$?([\d.]+)/i))
                admin_fee = parse_price(m[1])
              end
            end

            web_special_note ||= safe_text(card, ".unit-card__cost__web__online-rate")
          end

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price,
            web_special_note:   web_special_note,
            admin_fee:          admin_fee,
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

  # Parses "Phoenix, AZ 85042" (or "Phoenix , AZ 85042" — extra space seen
  # in the wild) into [city, state, zip].
  def parse_city_state_zip(text)
    return [ nil, nil, nil ] if text.blank?

    match = text.match(/^(.+?)\s*,\s*([A-Za-z]{2})\s+(\d{5})/)
    return [ nil, nil, nil ] unless match

    [ match[1].strip, match[2].strip.upcase, match[3].strip ]
  end
end
