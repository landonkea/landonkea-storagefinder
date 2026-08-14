# =============================================================================
# EXTRA SPACE STORAGE PARSER
# =============================================================================
# Crawls extraspace.com to find storage facilities and unit pricing.
#
# Website behavior notes:
#   - Location search uses a lat/lng based URL parameter
#   - Location list renders via JavaScript (must wait for it)
#   - Unit pricing page uses React, prices load after initial page render
#   - "Web Rate" is the online-only discounted price
#   - "Street Rate" is the walk-in regular price
#   - We capture both and store web rate as web_special_price
#
# If the site layout changes and this parser breaks, run the recon tool:
#   rails runner "ReconService.run('https://www.extraspace.com/storage/find-storage/in/gilbert-az/')"
# =============================================================================

# NOVICE PRIMER: `class Companies::ExtraSpace < Companies::BaseParser` makes
# this class a SUBCLASS ("child class") of `Companies::BaseParser` (see
# app/services/companies/base_parser.rb), it INHERITS every method
# BaseParser defines (`run`, `safe_text`, `safe_attr`, `parse_price`,
# `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`, etc.) and only needs to implement the 4 methods
# unique to Extra Space's website. "Playwright" is the browser-automation
# library: a `page` object represents one open, invisible ("headless")
# browser tab, and CSS-selector strings (like "[data-testid='facility-card']")
# are the same mini-language stylesheets use to target HTML elements, see
# base_parser.rb's opening comment for a fuller explanation of selectors and
# of Ruby's `protected`/`private` visibility keywords, both used here too.
#
# FLAG (still unverified, see attempt below): unlike the sibling parsers
# in this folder (cube_smart.rb, devon_self_storage.rb, public_storage.rb,
# etc.), this file's header has none of the "verified by driving the live
# site" recon detail those files carry, and nearly every selector below is
# written as a long, speculative comma-separated CSS list (e.g.
# "[data-testid='facility-card'], .facility-card, .search-result-item")
# rather than one selector confirmed against real HTML.
#
# ReconService was actually run against the live URL in this file's header
# comment to try to verify/fix these selectors. The result: extraspace.com
# served a PerimeterX "Press & Hold to confirm you are a human (and not a
# bot)" CAPTCHA challenge instead of the real search-results page, no
# facility/unit HTML was returned at all, so there was nothing to check
# these selectors against. This means the speculative selectors below are
# STILL unverified, but now for a more serious reason than "nobody checked
# yet": this site may reject this app's own automated crawls in production
# the same way, independent of whether these selectors are correct. If
# real crawls against Extra Space are failing, check the logs for this
# same "Access to this page has been denied" / CAPTCHA pattern before
# assuming it's a selector problem.
class Companies::ExtraSpace < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS name) holding Extra Space's website root,
  # reused below when building absolute URLs from relative "/foo" links.
  BASE_URL = "https://www.extraspace.com"

  # How many miles to expand the search if no results come back initially.
  # NOTE: nothing in this file actually reads FALLBACK_RADIUS_EXPANSION,
  # see the "flag but don't fix" notes at the end of this review.
  FALLBACK_RADIUS_EXPANSION = 10

  # Overrides BaseParser's abstract `company_name`, required display name
  # shown in the UI/exports for this company.
  def company_name
    "Extra Space Storage"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug`, short id used in log
  # lines and screenshot filenames.
  def company_slug
    "extra_space"
  end
  # `end` closes `def company_slug`.

  # Build the search URL for a given lat/lng and radius.
  # Extra Space uses lat/lng in the query string.
  def search_url(lat, lng, radius_miles)
    # Extra Space's search endpoint accepts lat, lng, and radius directly,
    # unlike several sibling parsers in this folder, no reverse-geocoding
    # step is needed here.
    "#{BASE_URL}/storage/find-storage/?lat=#{lat}&lng=#{lng}&radius=#{radius_miles}&sort=distance"
    # String interpolation (`#{...}`) builds the URL by inserting the raw
    # `lat`, `lng`, and `radius_miles` values directly into the query
    # string. This is the method's only expression, so it's the return
    # value.
  end
  # `end` closes `def search_url`.

  # Parse the list of storage locations from the search results page.
  # Returns an array of location hashes.
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per facility found.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block, code
      # inside `begin` runs normally; an error jumps to the matching
      # `rescue` clause instead of crashing this method outright.
      # Wait for the location list to appear, it renders via JavaScript.
      # The selector ".facility-results-list" is the container for all
      # results.
      log_info("Waiting for location results to render...")

      page.wait_for_selector(
        ".facility-results-list, .no-results-message, [data-testid='facility-card']",
        timeout: 15_000
      )
      # A comma inside a CSS selector string means "OR", this call waits
      # for ANY ONE of these three possible elements to appear (whichever
      # shows up first: the results container, an explicit "no results"
      # message, or an individual facility card), with a 15-second (15,000ms)
      # ceiling. Unlike some sibling parsers, there's no trailing
      # `rescue nil` here, so a full timeout (none of the three ever
      # appearing) raises and is handled by the `rescue Playwright::TimeoutError`
      # clause further down.

      # Check if "no results" message appeared, means no locations in this
      # area.
      no_results = page.query_selector(".no-results-message, [data-testid='no-results']")
      # `query_selector` (no "_all") returns just the FIRST matching element,
      # or `nil` if none match. Again, the comma means "match either of
      # these two selectors."
      if no_results
        # A bare `if some_object` treats anything that isn't `nil`/`false` as
        # "truthy", so this runs only when an actual element was found.
        log_warning("Extra Space returned 'no results' for this search area")
        return []
        # Exits `parse_locations` immediately with an empty array, an
        # explicit "no results" message means there's nothing to scrape.
      end
      # `end` closes the `if no_results` block.

      # Find all facility cards in the results list.
      # Each card represents one storage location.
      facility_cards = page.query_selector_all(
        "[data-testid='facility-card'], .facility-card, .search-result-item"
      )
      # `query_selector_all` finds EVERY element matching any of these three
      # comma-separated selectors, returning them as an Array (empty, not
      # nil, if none match).

      if facility_cards.empty?
        # `.empty?` is true for a zero-length Array.
        log_warning(
          "Could not find facility cards on Extra Space search page. " \
          "The site may have updated its layout. " \
          "Expected selector: '[data-testid=facility-card]'. " \
          "Run ReconService to get current selectors."
        )
        # The trailing `\` at each line's end continues the string literal
        # onto the next source line without inserting a real newline,
        # purely to keep source lines from getting too long; the pieces
        # concatenate into one message.
        take_error_screenshot(page, "no_facility_cards")
        # Inherited helper: saves a screenshot of the current page to
        # logs/, tagged with this label, to help a developer see what
        # actually rendered.
        return []
      end
      # `end` closes the `if facility_cards.empty?` block.

      log_info("Found #{facility_cards.length} facility cards, extracting details")

      facility_cards.each_with_index do |card, index|
        # `.each_with_index do |element, index| ... end` walks every element
        # of `facility_cards`, running the block once per card, handing it
        # to the block as `card` and its 0-based position as `index`.
        begin
          # Inner begin/rescue: an error on ONE card shouldn't stop the rest
          # of the cards from being processed.
          # Extract the facility name.
          name = safe_text(card, "[data-testid='facility-name'], .facility-name, h3")
          # Inherited helper: finds the first element inside `card` matching
          # any of these three selectors and returns its trimmed text, or
          # `nil` if none matched.

          # Extract the address, Extra Space usually has separate elements
          # for each part.
          street  = safe_text(card, "[data-testid='address-street'], .address-street, .street-address")
          city    = safe_text(card, "[data-testid='address-city'], .address-city")
          state   = safe_text(card, "[data-testid='address-state'], .address-state")
          zip     = safe_text(card, "[data-testid='address-zip'], .address-zip, .postal-code")
          # Four separate `safe_text` calls, each targeting a different
          # (guessed) selector for one piece of the address, unlike some
          # sibling parsers that split one combined "street, city, state
          # zip" text block, this assumes Extra Space's markup exposes each
          # address component as its own separate element.

          # Phone number (may not always be present on the list view).
          phone   = safe_text(card, "[data-testid='phone'], .facility-phone, .phone-number")

          # The link to this facility's detail/pricing page.
          link_element = card.query_selector("a[href*='/storage/find-storage/']")
          # `[href*='...']` is an attribute selector meaning "href CONTAINS
          # this substring anywhere" (`*=` = "contains", as opposed to `^=`
          # "starts with" or `$=` "ends with").
          relative_url = link_element&.get_attribute("href")
          # `&.` safely reads the `href` attribute only if `link_element`
          # isn't `nil`.
          facility_url = relative_url ? "#{BASE_URL}#{relative_url}" : nil
          # Ternary: builds a full URL by prefixing `BASE_URL` if a relative
          # URL was found; otherwise `nil`.

          # Extract Extra Space's internal facility ID from the URL or data
          # attributes. This helps us avoid creating duplicates on future
          # crawls.
          external_id = card.get_attribute("data-facility-id") ||
                        card.get_attribute("data-id") ||
                        extract_id_from_url(facility_url)
          # `||` ("or") chains three fallbacks: try the `data-facility-id`
          # attribute first; if that's `nil`, try `data-id`; if that's also
          # `nil`, fall back to parsing an ID out of the URL itself via the
          # private helper defined near the bottom of this file. Ruby
          # evaluates left to right and stops at the first non-nil/non-false
          # value.

          # Skip this card if we couldn't get a valid name or address.
          if name.blank? || street.blank?
            # `.blank?` (Rails helper) is true for `nil`, empty string, or
            # whitespace-only string. `||` means either missing field is
            # enough to skip this card.
            log_warning(
              "Facility card ##{index + 1} is missing name or street address, skipping. " \
              "This may indicate a layout change in this part of the page."
            )
            next
            # `next` skips the rest of THIS block iteration (this one card)
            # and moves on to the next card in the loop.
          end
          # `end` closes the `if name.blank? || street.blank?` block.

          locations << {
            # `<<` appends a new Hash (one location) onto the `locations`
            # array.
            name:        name,
            address:     street,
            city:        city || "",
            # `||` falls back to an empty string if `city` came back `nil`.
            state:       state || "AZ",
            # Falls back to the literal string "AZ" if no state was
            # scraped, see the "flag but don't fix" notes at the end of
            # this review regarding this hardcoded regional default.
            zip:         zip || "",
            phone:       phone,
            url:         facility_url,
            external_id: external_id
          }

          log_info("  ✓ Location #{index + 1}: #{name}, #{street}, #{city}")
          # A checkmark-prefixed info log line for each successfully parsed
          # location, useful for eyeballing crawl progress in the logs.

        rescue => e
          # A bare `rescue => e` (no exception class named) catches
          # `StandardError` and its subclasses, "any ordinary error", and
          # captures the exception object into local variable `e`.
          log_warning("Error parsing facility card ##{index + 1}: #{e.class}: #{e.message}")
          # Keep going, don't let one bad card kill the whole list.
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `facility_cards.each_with_index do |card, index| ... end`
      # loop.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue catches a timeout from `wait_for_selector` above
      # (or anywhere else in the surrounding `begin` block), captures the
      # exception object as `e`.
      log_error(
        "Timed out waiting for Extra Space location results to render. " \
        "The page took longer than 15 seconds. " \
        "This can happen on slow hardware or slow internet. " \
        "Try increasing PAGE_TIMEOUT_MS in base_parser.rb. " \
        "Error: #{e.message}"
      )
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # A bare `rescue => e` must come AFTER the more specific
      # `Playwright::TimeoutError` rescue, Ruby checks clauses top-to-bottom
      # and uses the first one that matches, so this is the catch-all for
      # anything else unexpected.
      log_error("Unexpected error parsing Extra Space location list: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # The last expression evaluated, the `locations` Array built above,
    # becomes `parse_locations`'s return value.
  end
  # `end` closes `def parse_locations`.

  # Parse unit sizes and prices from a facility's pricing page.
  # Returns an array of unit attribute hashes.
  def parse_units(page, facility)
    units = []
    # Empty Array to collect one Hash per unit found.

    begin
      log_info("Loading pricing page for #{facility.name}")

      # Wait for the unit grid to render.
      page.wait_for_selector(
        ".unit-grid, [data-testid='unit-list'], .storage-units, .units-container",
        timeout: 15_000
      )
      # Waits up to 15 seconds for ANY ONE of these four comma-separated
      # (i.e. "OR"-joined) selectors to appear on the page.

      # Extra Space sometimes has a "Climate Controlled" tab that needs
      # clicking. Try clicking it, if it doesn't exist, that's fine, we
      # just continue.
      cc_tab = page.query_selector("[data-filter='climate-controlled'], button[data-unit-type='climate']")
      # Note: We do NOT click this, we want ALL unit types and filter
      # ourselves. This just tells us the tab exists (useful for debugging
      # if needed).
      # NOTE: `cc_tab` is assigned here but never read again anywhere below
      # , see the "flag but don't fix" notes at the end of this review; as
      # written, this line performs a page lookup whose result is discarded.

      # Find all unit rows/cards on the page.
      unit_elements = page.query_selector_all(
        "[data-testid='unit-card'], .unit-row, .unit-item, .storage-unit-card"
      )
      # Again, four comma-separated ("OR") selectors, finds every matching
      # element as an Array.

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
      # `end` closes the `if unit_elements.empty?` block.

      log_info("Found #{unit_elements.length} unit elements on page, parsing each")

      unit_elements.each_with_index do |el, index|
        begin
          # Size: usually something like "10' × 10'" or "10x10".
          raw_size = safe_text(el, "[data-testid='unit-size'], .unit-size, .size-label, h3, h4")
          size     = parse_size(raw_size)
          # Inherited helper: extracts the two numbers out of the raw size
          # text and normalizes them to a "10x10" string, or `nil` on
          # failure.

          if size.blank?
            log_warning("Could not determine size for unit ##{index + 1} at #{facility.name}, skipping")
            next
            # Skip this unit, without a size, there's nothing usable to
            # save.
          end
          # `end` closes the `if size.blank?` block.

          # Street rate (regular walk-in price).
          street_rate_text = safe_text(el, "[data-testid='street-rate'], .street-rate, .regular-price")
          monthly_price    = parse_price(street_rate_text)
          # Inherited helper: strips non-numeric characters and converts to
          # a Float, or `nil` if unparseable.

          # Web rate (online promotional price, lower than street rate).
          web_rate_text     = safe_text(el, "[data-testid='web-rate'], .web-rate, .online-price, .special-price")
          web_special_price = parse_price(web_rate_text)

          # Web special note (e.g. "First month free" or "Online only").
          web_special_note = safe_text(el, "[data-testid='promotion-text'], .promo-text, .special-note")

          # Is this unit climate controlled?
          # Extra Space uses data attributes OR text labels for this.
          cc_attr = el.get_attribute("data-climate-controlled") ||
                    el.get_attribute("data-feature-climate")
          # `||` tries the first attribute; if `nil`, tries the second.
          cc_text = safe_text(el, ".feature-tag, .unit-feature, [data-testid='features']")
          climate_controlled = cc_attr == "true" ||
                               cc_text.to_s.downcase.include?("climate") ||
                               cc_text.to_s.downcase.include?("temperature")
          # `climate_controlled` is true if ANY of three checks pass: the
          # data attribute literally equals the string "true", OR the
          # feature text (lower-cased, `.to_s` guarding against `nil`)
          # contains "climate", OR it contains "temperature".

          # Is the unit available?
          # Extra Space marks unavailable units with a class or data
          # attribute.
          unavailable = el.get_attribute("data-available") == "false" ||
                        el.query_selector(".sold-out, .unavailable, [data-status='unavailable']").present?
          # `.present?` here is called on whatever `query_selector` returns
          # , a Playwright element object or `nil`; `.present?` (from Rails,
          # via ActiveSupport being loaded everywhere in this Rails app) is
          # true for anything that isn't nil/blank, so this is true only if
          # a matching "sold out"/"unavailable" element was actually found.
          available = !unavailable
          # `!` negates the boolean, available is the opposite of
          # unavailable.

          # Unit type, try to detect locker, parking, etc. from text.
          features_text = safe_text(el, ".features-list, .unit-features, .amenities") || ""
          # Falls back to an empty string if no features text was found, so
          # the private helper below never has to handle `nil`.
          unit_type     = detect_unit_type(features_text, size)
          # Calls the private helper (defined further down) that inspects
          # the features text for keywords and returns a unit_type string.

          # Is this a drive-up unit?
          drive_up = features_text.downcase.include?("drive-up") ||
                     features_text.downcase.include?("drive up") ||
                     features_text.downcase.include?("outdoor")
          # True if the lower-cased features text contains any of these
          # three substrings.

          # Is it indoor?
          indoor = !drive_up && unit_type != "outdoor"
          # A unit only counts as indoor if it's not drive-up AND its
          # detected unit_type isn't "outdoor".

          # The booking link for this specific unit.
          booking_link = safe_attr(el, "a[href*='reserve'], a[href*='book'], a.reserve-button", "href")
          # Inherited helper: finds the first matching link and returns its
          # `href` attribute value, or `nil`.
          booking_url  = booking_link ? "#{BASE_URL}#{booking_link}" : facility.facility_url
          # Ternary: build a full URL from the per-unit link if found;
          # otherwise fall back to the general facility page URL.

          # Admin fee (sometimes shown per-unit, sometimes facility-wide).
          admin_fee_text = safe_text(el, ".admin-fee, [data-testid='admin-fee']")
          admin_fee      = parse_price(admin_fee_text)

          # Insurance note (Extra Space often requires it).
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
          # Keep going, don't let one bad unit kill the rest.
        end
        # `end` closes the inner `begin ... rescue ... end` for one unit.
      end
      # `end` closes the `unit_elements.each_with_index do |el, index| ... end`
      # loop.

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
      # `e.backtrace` is an Array of Strings describing the call stack where
      # the error happened; `.first(5)` takes the first 5 entries and
      # `.join(" | ")` glues them into one readable string, rather than
      # dumping a giant raw stack trace into the log.
      take_error_screenshot(page, "units_error_#{facility.id}")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    units
    # Return value: the array of unit Hashes built above.
  end
  # `end` closes `def parse_units`.

  # ---------------------------------------------------------------------------
  # PRIVATE HELPERS
  # ---------------------------------------------------------------------------
  private
  # Ruby's `private` keyword: everything below this line can only be called
  # from inside this class's own methods (with an implicit receiver), never
  # from outside code, these are internal implementation details.

  # Try to extract a numeric facility ID from a URL.
  # Extra Space URLs often look like: /storage/find-storage/in/gilbert-az/1234567/
  def extract_id_from_url(url)
    return nil if url.blank?
    # `.blank?` is true for `nil`/empty/whitespace-only, nothing to search
    # if there's no URL at all.

    # Look for a sequence of 6+ digits in the URL path.
    match = url.match(/\/(\d{6,})/)
    # `.match(regex)` searches `url` for the first place the pattern
    # matches, returning a `MatchData` object (or `nil` if no match). The
    # pattern `/\/(\d{6,})/` means: a literal "/" character, followed by a
    # captured group (the parentheses) of `\d{6,}`, "a digit, repeated 6 or
    # more times" (`{6,}` is a regex "repetition" quantifier with no upper
    # bound). This targets a long numeric ID segment in the URL path, like
    # ".../1234567/".
    match ? match[1] : nil
    # Ternary: if a match was found, `match[1]` reads the text captured by
    # the first parenthesized group (the digits themselves, without the
    # leading slash); otherwise return `nil`. This is the method's last
    # expression, so it's the return value.
  end
  # `end` closes `def extract_id_from_url`.

  # Detect what type of unit this is based on its features text and size.
  # Returns a unit_type string that matches our EXCLUDED_TYPES list.
  def detect_unit_type(features_text, size)
    text = features_text.to_s.downcase
    # `.to_s` guards against `nil`, `.downcase` lower-cases everything so
    # the keyword checks below are case-insensitive.

    return "parking"    if text.include?("parking")
    return "rv"         if text.include?("rv") || text.include?("recreational vehicle")
    return "boat"       if text.include?("boat")
    return "locker"     if text.include?("locker")
    return "mailbox"    if text.include?("mailbox") || text.include?("mail box")
    return "vehicle"    if text.include?("vehicle storage") || text.include?("car storage")
    return "motorcycle" if text.include?("motorcycle")
    return "outdoor"    if text.include?("outdoor") || text.include?("outside")
    # Each line is a one-line `return VALUE if CONDITION`, Ruby's postfix
    # `if` modifier runs the `return` only when the condition is true, and
    # since `return` exits the method immediately, only the FIRST matching
    # keyword wins; later checks never even run once one has already
    # returned. Note the `size` parameter is accepted but never actually
    # used anywhere in this method body, see the "flag but don't fix" notes
    # at the end of this review.

    # If none of the exclusion keywords match, it's a standard unit.
    "standard"
    # Reached only if none of the `return` lines above fired, this becomes
    # the method's return value in that case.
  end
  # `end` closes `def detect_unit_type`.
end
# `end` closes `class Companies::ExtraSpace`.
