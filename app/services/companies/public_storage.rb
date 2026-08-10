# =============================================================================
# PUBLIC STORAGE PARSER
# =============================================================================
# Crawls publicstorage.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site, see recon/ for
# saved HTML/screenshots):
#   - There is no lat/lng search endpoint. The search page takes a free-text
#     `location` query param: /self-storage-search?location=<City, State>.
#     We reverse-geocode the lat/lng we're given into a city/state via the
#     Geocoder gem (already configured for forward geocoding elsewhere).
#   - Search results AND facility detail pages both render facility/unit data
#     server-side under `.store-container` / `.unit-list-item`, no separate
#     JSON API call needed.
#   - "$1 first month" / "Online price" deals are common, captured as
#     web_special_price.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.publicstorage.com/self-storage-search?location=Gilbert%2C+Arizona')"
# =============================================================================

# NOVICE PRIMER: `class Companies::PublicStorage < Companies::BaseParser`
# makes this class a SUBCLASS ("child class") of `Companies::BaseParser`
# (see app/services/companies/base_parser.rb), it INHERITS every method
# BaseParser defines (`run`, `safe_text`, `safe_attr`, `parse_price`,
# `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`, etc.) and only needs to implement the 4 methods
# unique to Public Storage's own website. "Playwright" is the
# browser-automation library: a `page` object represents one open, invisible
# ("headless") browser tab, and CSS-selector strings (like
# ".store-container") are the same mini-language stylesheets use to target
# HTML elements, see base_parser.rb's opening comment for a fuller
# explanation of selectors and Ruby's `protected`/`private` keywords, both
# used here too.
class Companies::PublicStorage < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS name) holding Public Storage's website root,
  # reused below when building absolute URLs from relative "/foo" links.
  BASE_URL = "https://www.publicstorage.com"

  # Overrides BaseParser's abstract `company_name`, required display name
  # shown in the UI/exports for this company.
  def company_name
    "Public Storage"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug`, short id used in log
  # lines and screenshot filenames.
  def company_slug
    "public_storage"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url`, builds the URL for
  # Public Storage's search-results page given GPS coordinates (radius_miles
  # is accepted for interface compatibility with BaseParser#run, but this
  # site has no radius parameter to pass it through to).
  def search_url(lat, lng, radius_miles)
    location_query = reverse_geocode_city_state(lat, lng)
    # Calls the private helper (near the bottom of this file) that turns raw
    # GPS coordinates into a "City, State" string, this site's search box
    # takes free text, not coordinates.
    "#{BASE_URL}/self-storage-search?location=#{ERB::Util.url_encode(location_query)}"
    # String interpolation builds the URL. `ERB::Util.url_encode`
    # percent-encodes the "City, State" string so spaces/commas survive
    # inside a URL query string. This is the method's only expression, so
    # it's the return value.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations`, reads the list of
  # nearby Public Storage facilities off the search-results page.
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per facility found.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block, code
      # inside `begin` runs normally; an error jumps to the matching
      # `rescue` clause instead of crashing this method.
      # NOTE: .no-stores-results-content is present in the DOM on every page
      # load (just hidden via CSS when there are results), so it can't be
      # used as a presence check, .store-container count is the real
      # signal.
      page.wait_for_selector(".store-container", timeout: 15_000) rescue nil
      # Waits up to 15 seconds (15,000ms) for at least one facility card to
      # appear. The trailing `rescue nil` is Ruby's one-line rescue
      # modifier: any error here (most likely a timeout, if this search area
      # has zero results) is swallowed and the whole expression becomes
      # `nil`, execution simply continues to the next line, where
      # `query_selector_all` will find zero cards and the "empty" branch
      # below handles that cleanly.

      cards = page.query_selector_all(".store-container")
      # Finds every facility-card element on the page, returns an empty
      # Array, never nil, if none match.

      if cards.empty?
        # `.empty?` is true for a zero-length Array.
        log_warning(
          "No facility cards found on Public Storage search page (selector: '.store-container'). " \
          "Run ReconService to check current page structure."
        )
        # The trailing `\` continues the string literal onto the next
        # source line without a real newline, purely for keeping source
        # lines from getting too long; the pieces concatenate into one
        # message.
        take_error_screenshot(page, "no_cards")
        # Inherited helper: saves a screenshot of the current page to logs/,
        # tagged with this label, for later debugging.
        return []
        # Exits `parse_locations` immediately, nothing left to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} Public Storage locations")
      # `.length` on an Array returns how many elements it has.

      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` walks every element
        # of `cards`, running the block once per card, handing it to the
        # block as `card` and its 0-based position as `idx`.
        begin
          # Inner begin/rescue: an error parsing ONE card shouldn't stop the
          # rest of the cards from being processed.
          link    = card.query_selector("a.plp-link")
          # Finds the facility-detail link inside this card.
          rel_url = link&.get_attribute("href")
          # `&.` safely reads the `href` attribute only if `link` isn't
          # `nil`.
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil
          # Ruby's ternary operator (`condition ? a : b`): builds a full
          # absolute URL if a relative one was found; otherwise `url` is
          # `nil`.

          address_lines = safe_text(card, ".store-address")&.split(",")&.map(&:strip)&.reject(&:blank?) || []
          # A chain of `&.` (safe navigation) calls: `safe_text(...)` may
          # return `nil` if no address element was found, so every step
          # after it uses `&.` to avoid crashing on `nil`, `.split(",")`
          # breaks the address text on commas, `.map(&:strip)` trims
          # whitespace off each piece (`&:strip` is shorthand for
          # `{ |s| s.strip }`), `.reject(&:blank?)` drops any resulting
          # blank pieces. If ANY link in that chain returns `nil` (e.g.
          # `safe_text` itself found nothing), the whole chain short-circuits
          # to `nil`, and the trailing `|| []` then falls back to an empty
          # Array so the indexing below never crashes.
          street        = address_lines[0]
          city          = address_lines[1]
          # Last line is "AZ 85296" (state + zip together).
          state_zip     = address_lines[2].to_s.split(/\s+/)
          # `.to_s` guards against `address_lines[2]` being `nil` (if there
          # were fewer than 3 address pieces). `.split(/\s+/)` splits on
          # one-or-more whitespace characters (`\s+` is a regex meaning "one
          # or more spaces/tabs"), turning "AZ 85296" into ["AZ", "85296"].
          state         = state_zip[0]
          zip           = state_zip[1]

          external_id = card.get_attribute("data-storeid")
          # Reads Public Storage's own internal store ID off a custom
          # `data-storeid` HTML attribute, the most reliable way to
          # recognize "this is the same facility we saw before."

          next if street.blank?
          # `.blank?` (Rails helper) is true for `nil`/empty/whitespace-only.
          # `next` skips the rest of THIS block iteration (this one card)
          # and moves to the next card, reached when we couldn't even get a
          # usable street address.

          locations << {
            # `<<` appends a new Hash (one location) onto the `locations`
            # array.
            name:        "Public Storage - #{street}",
            # Public Storage's search results don't include a distinct
            # facility "name" separate from its address, so we build one by
            # convention: "Public Storage - <street>".
            address:     street,
            city:        city || "",
            # `||` falls back to an empty string if `city` came back `nil`.
            state:       state || "AZ",
            # Falls back to the literal string "AZ" if no state was
            # scraped, see the "flag but don't fix" notes at the end of
            # this review regarding this hardcoded regional default.
            zip:         zip || "",
            phone:       nil,
            # No phone number is exposed on Public Storage's search-results
            # cards in what we scrape, left `nil`.
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street}, #{city}, #{state}")
          # A checkmark-prefixed info log line for each successfully parsed
          # location, useful for eyeballing crawl progress in the logs.

        rescue => e
          # A bare `rescue => e` (no exception class named) catches
          # `StandardError` and its subclasses, capturing the exception
          # object into local variable `e`.
          log_warning("Error parsing Public Storage card ##{idx + 1}: #{e.class}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue catches a `Playwright::TimeoutError` happening
      # anywhere else in the surrounding `begin` block (not already
      # swallowed by the `rescue nil` above).
      log_error("Timeout waiting for Public Storage search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # This bare rescue must come AFTER the more specific one, Ruby checks
      # `rescue` clauses top-to-bottom and uses the first one that matches,
      # so this is the catch-all for anything else unexpected.
      log_error("Unexpected error parsing Public Storage locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # The last expression evaluated, the `locations` Array built above,
    # becomes `parse_locations`'s return value.
  end
  # `end` closes `def parse_locations`.

  # Overrides BaseParser's abstract `parse_units`, reads unit sizes/prices
  # off one facility's own detail page.
  def parse_units(page, facility)
    units = []
    # Empty Array to collect one Hash per unit found.

    begin
      page.wait_for_selector(".unit-list-item", timeout: 15_000)
      # Waits up to 15 seconds for at least one unit row to render. No
      # trailing `rescue nil` here, a timeout on a facility's own detail
      # page (which we already know exists) is treated as a real error,
      # handled by the `rescue Playwright::TimeoutError` clause further
      # down.

      unit_els = page.query_selector_all(".unit-list-item")
      # Finds every unit row on this facility's detail page.

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.unit-list-item'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
        # Exits early with an empty array, nothing more to parse.
      end
      # `end` closes the `if unit_els.empty?` block.

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".size")
          # Reads the raw size text (e.g. "10' x 10'") for this unit.
          size     = parse_size(raw_size)
          # Inherited helper: extracts the two numbers and normalizes them
          # to a "10x10"-style string, or `nil` on failure.
          next if size.blank?
          # Skip this unit if we couldn't determine a usable size.

          # The real numeric price lives in a data attribute, more
          # reliable than parsing the "$26" text nodes.
          price_el      = el.query_selector(".unit-price[data-pricebook-price]")
          # `[data-pricebook-price]` (with no `=value`) is an attribute
          # selector meaning "has this attribute at all, regardless of its
          # value", matches a ".unit-price" element that carries a
          # "data-pricebook-price" attribute.
          monthly_price = price_el&.get_attribute("data-pricebook-price")&.to_f
          # `&.` chains safely handle `price_el` being `nil` (no such
          # element found), if it exists, reads the attribute's raw string
          # value and converts it to a Float with `.to_f`.
          monthly_price = nil if monthly_price.blank? || monthly_price <= 0
          # Treats a missing, blank, zero, or negative price as "no real
          # price" by resetting it to `nil`, a price that low doesn't make
          # sense for a storage unit.

          list_price = price_el&.get_attribute("data-list-price")&.to_f
          # Same safe-navigation pattern, reading a second data attribute
          # that holds the (potentially higher) "list" price.
          web_special_price = nil
          web_special_note  = nil
          # Initialize both to nil before deciding whether a promo situation
          # applies, below.
          if list_price.present? && list_price > 0 && monthly_price.present? && list_price > monthly_price
            # `.present?` is true for non-nil/non-blank values. Only treat
            # this as a "web special" if the list price is a real positive
            # number AND we have a monthly_price AND the list price is
            # genuinely higher than it.
            web_special_price = monthly_price
            # The lower price (what we first read as `monthly_price`) is
            # actually the promotional online rate.
            web_special_note  = "Online price"
            monthly_price     = list_price
            # Re-assign `monthly_price` to the higher list price, so it
            # represents the "regular" price and `web_special_price` holds
            # the discount, matching the convention used by sibling
            # parsers in this folder.
          end
          # `end` closes the `if list_price.present? && ...` block.

          classes             = el.get_attribute("class").to_s
          # Reads this element's full `class` HTML attribute as one string
          # (e.g. "unit-item ClimateControl IsDriveUpAccess"), `.to_s`
          # guarding against `nil`.
          climate_controlled  = classes.include?("ClimateControl")
          # `.include?` checks whether that class string contains this
          # exact substring anywhere.
          drive_up            = classes.include?("IsDriveUpAccess")
          indoor              = !drive_up
          # A unit counts as indoor simply if it's not drive-up, for this
          # company.
          is_vehicle          = classes.include?("IsVehicleUnit")

          sold_out  = el.query_selector(".sold-out, .unavailable") ? true : false
          # `query_selector` returns an element object or `nil`; the
          # ternary converts that into an explicit `true`/`false` boolean
          # rather than leaving it as an element-or-nil value.
          available = !sold_out
          # `!` negates the boolean.

          unit_type = is_vehicle ? "vehicle" : "standard"
          # Ternary: "vehicle" if the vehicle-unit class was present;
          # otherwise "standard".

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
            # Public Storage's unit markup doesn't carry a per-unit
            # reservation link, every unit just points back at the general
            # facility detail page.
          }

        rescue => e
          log_warning("Error parsing unit ##{idx + 1} at #{facility.name}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one unit.
      end
      # `end` closes the `unit_els.each_with_index do |el, idx| ... end`
      # loop.

    rescue Playwright::TimeoutError => e
      log_error("Timeout waiting for units at #{facility.name}: #{e.message}")
      take_error_screenshot(page, "units_timeout_#{facility.id}")
    rescue => e
      log_error("Error parsing units at #{facility.name}: #{e.class}: #{e.message}")
      take_error_screenshot(page, "units_error_#{facility.id}")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    units
    # Return value: the array of unit Hashes built above.
  end
  # `end` closes `def parse_units`.

  private
  # Ruby's `private` keyword: everything below this line can only be called
  # from inside this class's own methods (implicit receiver only), never
  # from outside code, these are internal implementation details.

  # Public Storage's search box takes a free-text "City, State" query, not
  # coordinates, reverse-geocode what we were given back into that form.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    # `Geocoder` is a third-party Ruby gem providing geocoding (address <->
    # coordinates lookups). `.search([lat, lng])` performs a "reverse
    # geocode", coordinates in, real-world address out, returning an
    # Array of matches; `.first` takes the best one, which may be `nil`.
    if result&.city.present?
      # `&.` safely reads `.city` only if `result` isn't `nil`; `.present?`
      # is then true if that city string is real/non-blank.
      "#{result.city}, #{result.state}"
      # Builds a "City, State" string, e.g. "Gilbert, Arizona", this is the
      # last expression of this branch, and (since the whole if/else is the
      # method's last expression) the method's return value on success.
    else
      "#{lat},#{lng}"
      # Fallback if geocoding failed: return the raw coordinates as a
      # string. Won't match a real city, but guarantees the method always
      # returns something rather than crashing.
    end
    # `end` closes the `if result&.city.present? ... else ... end` branch.
  rescue => e
    # A method-level rescue (attached directly to `def`, no separate
    # `begin` needed), catches any error from the geocoding call (e.g. a
    # network failure).
    log_warning("Reverse geocoding failed for #{lat},#{lng}: #{e.message}")
    "#{lat},#{lng}"
    # Same raw-coordinates fallback as the `else` branch above.
  end
  # `end` closes `def reverse_geocode_city_state`.
end
# `end` closes `class Companies::PublicStorage`.
