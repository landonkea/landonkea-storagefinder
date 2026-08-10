# =============================================================================
# ISTORAGE PARSER
# =============================================================================
# Crawls to find iStorage facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site with Playwright,
# see recon/ for a saved screenshot/report, and the exploration notes below):
#
#   - istorage.com is NOT an independent site anymore. Every single path on
#     istorage.com (including the recon URL istorage.com/storage-units/az/)
#     performs a full redirect to the equivalent nsastorage.com URL. The
#     homepage itself renders as "NSA Storage" branding and explicitly shows
#     an "NSA Storage Family of Brands" carousel (SecurCare, Northwest Self
#     Storage, RightSpace Storage, Move It Storage, Southern Self Storage,
#     iStorage, ...). This is normal corporate site consolidation, not bot
#     detection, no CAPTCHA/"press & hold"/challenge page was ever shown.
#   - The site's own header/search-page search form
#     (id="headerSearchForm" / id="searchForm") POSTs via GET to
#     `https://www.nsastorage.com/search-results?location=<City, State>`,
#     which itself redirects to a friendly URL like
#     `/storage/<state>/storage-units-<city>`. We drive that endpoint
#     directly with a reverse-geocoded "City, State" string (same technique
#     as Companies::PublicStorage, there's no lat/lng search endpoint).
#   - IMPORTANT: nsastorage.com's search-results page returns the nearest
#     facilities from ALL NSA brands mixed together, sorted by distance,
#     not just iStorage. Each result card has a brand-qualified title
#     (e.g. "RightSpace Storage | N Gilbert Rd" or "iStorage | W Davis St").
#     We MUST filter to only cards whose title starts with "iStorage",
#     otherwise we'd be saving RightSpace/SecurCare/etc. facilities under the
#     iStorage company name. In some markets (e.g. Phoenix/Gilbert, AZ, that
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
#     the facility search), like Public Storage's `.no-stores-results-content`
#     trap, its presence can't be used as a signal. We rely on actual counts
#     of `.facility-card` / `.unit-select-item` instead.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.nsastorage.com/storage')"
# =============================================================================

# NOVICE PRIMER: `class Companies::IStorage < Companies::BaseParser` makes
# this class a SUBCLASS ("child class") of `Companies::BaseParser` (see
# app/services/companies/base_parser.rb), it INHERITS every method
# BaseParser defines (`run`, `safe_text`, `safe_attr`, `safe_all_text`,
# `parse_price`, `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`, etc.) and only needs to implement the 4 methods
# unique to iStorage's (really, nsastorage.com's) website. "Playwright" is
# the browser-automation library: a `page` object represents one open,
# invisible ("headless") browser tab, and CSS-selector strings (like
# ".facility-card") are the same mini-language stylesheets use to target
# HTML elements, see base_parser.rb's opening comment for a fuller
# explanation of selectors and Ruby's `protected`/`private` keywords, both
# used here too.
class Companies::IStorage < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS name) holding the real site's root, note
  # this is nsastorage.com, not istorage.com, per the header notes above.
  BASE_URL = "https://www.nsastorage.com"

  # Overrides BaseParser's abstract `company_name`, required display name
  # shown in the UI/exports. Note this is "iStorage" even though the
  # underlying site and BASE_URL are nsastorage.com, see header notes.
  def company_name
    "iStorage"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug`, short id used in log
  # lines and screenshot filenames.
  def company_slug
    "istorage"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url`, builds the URL for the
  # NSA Storage search-results page given GPS coordinates (radius_miles is
  # accepted for interface compatibility with BaseParser#run, but the site
  # has no radius parameter to pass it through to).
  def search_url(lat, lng, radius_miles)
    location_query = reverse_geocode_city_state(lat, lng)
    # Calls the private helper (near the bottom of this file) that turns raw
    # GPS coordinates into a "City, State" string, this site's search box
    # takes free text, not coordinates.
    "#{BASE_URL}/search-results?location=#{ERB::Util.url_encode(location_query)}"
    # String interpolation builds the URL. `ERB::Util.url_encode` percent-
    # encodes the "City, State" string so special characters (spaces,
    # commas) survive being embedded in a URL query string, e.g. "Gilbert,
    # Arizona" becomes safe characters like "Gilbert%2C+Arizona". This is the
    # method's only expression, so it's the return value.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations`, reads the list of
  # nearby facilities off the search-results page and filters it down to
  # just the ones actually branded "iStorage" (see header notes above for
  # why this filtering step is necessary).
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per iStorage-branded
    # facility found.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block, code
      # inside `begin` runs normally; an error jumps to a matching `rescue`
      # clause instead of crashing this method.
      page.wait_for_selector(".facility-card", timeout: 15_000) rescue nil
      # Waits up to 15 seconds (15,000ms) for at least one card to appear.
      # The trailing `rescue nil` is Ruby's one-line rescue modifier: any
      # error here (most likely a timeout, if this search area genuinely has
      # zero NSA-brand facilities nearby) is swallowed and the expression
      # becomes `nil`, execution just continues on to the next line, where
      # `query_selector_all` will simply find zero cards.

      all_cards = page.query_selector_all(".facility-card")
      # Finds EVERY facility card on the page, across ALL NSA brands (not
      # just iStorage yet), returns an empty Array, never nil, if none
      # match.

      if all_cards.empty?
        # `.empty?` is true for a zero-length Array.
        log_warning(
          "No facility cards found at all on the NSA Storage search page (selector: '.facility-card'). " \
          "The page layout may have changed. Run ReconService to check current page structure."
        )
        # The trailing `\` continues the string literal onto the next source
        # line without a real newline, purely a source-formatting choice;
        # the two pieces concatenate into one message.
        take_error_screenshot(page, "no_cards")
        # Inherited helper: saves a PNG of the current page to logs/,
        # tagged with this label, for later debugging.
        return []
        # Exits `parse_locations` immediately, literally zero cards of any
        # brand means there's nothing to filter or parse.
      end
      # `end` closes the `if all_cards.empty?` block.

      # nsastorage.com mixes results from every NSA brand (RightSpace,
      # SecurCare, Northwest, Move It, iStorage, ...) sorted by distance,
      # keep only the ones actually branded "iStorage".
      cards = all_cards.select do |card|
        # `.select do |element| ... end` (a.k.a. `.filter`) builds a NEW
        # array containing only the elements from `all_cards` for which the
        # block returns a truthy value.
        title = safe_text(card, "h3.part_title_1")
        # Inherited helper: reads the trimmed text of this card's title
        # heading, or `nil` if not found.
        title.present? && title.strip.start_with?("iStorage")
        # `.present?` (Rails helper) is true for non-blank text. `&&`
        # requires both sides true. `.start_with?("iStorage")` is a Ruby
        # String method that's true only if the string begins with exactly
        # that text, this is the block's last expression, so it's what
        # `.select` uses to decide whether to keep this card.
      end
      # `end` closes the `all_cards.select do |card| ... end` block. Its
      # result (the filtered Array) is assigned to `cards`.

      if cards.empty?
        log_warning(
          "Found #{all_cards.length} nearby facility card(s), but none were branded 'iStorage' " \
          "(other NSA Storage brands serve this market). Treating as no iStorage locations in range."
        )
        return []
        # This is a DIFFERENT "empty" case than the one above: cards of
        # OTHER brands did exist nearby, just none of them were iStorage,
        # still correctly returns an empty result, but with a more specific
        # log message (per the header notes, this is expected/correct
        # behavior in some markets, not a bug).
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} iStorage location(s) (out of #{all_cards.length} nearby NSA facilities)")

      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` walks every element
        # of the (now iStorage-only) `cards` array, handing each to the
        # block as `card` with its 0-based position as `idx`.
        begin
          # Inner begin/rescue: an error on ONE card shouldn't stop the rest
          # of the cards from being processed.
          link = card.query_selector("a.part_title_1")
          # Finds the title link (an `<a>` tag with class "part_title_1")
          # inside this card.
          url  = link&.get_attribute("href")
          # `&.` safely reads the `href` attribute only if `link` isn't
          # `nil`.

          external_id = url.to_s[/-(\d+)\z/, 1]
          # `.to_s` guards against `url` being `nil`. `[...]` with a regex
          # and a capture-group index is Ruby's "String#[]" pattern-match
          # form: it searches for `/-(\d+)\z/`, a literal hyphen, followed
          # by a captured group of one-or-more digits, anchored to the very
          # END of the string (`\z` matches only the absolute end, unlike
          # `$` which can also match before a trailing newline), and
          # returns just the text captured by that group (the trailing
          # numeric facility ID), or `nil` if the pattern doesn't match.

          address_line = safe_text(card, "address")
          # Reads this card's single-line address text, e.g.
          # "123 Main St, Gilbert, AZ 85296".
          address_parts = address_line.to_s.split(",").map(&:strip).reject(&:blank?)
          # `.to_s` guards against `nil`. `.split(",")` breaks the line on
          # every comma. `.map(&:strip)` trims whitespace off each piece
          # (`&:strip` is shorthand for `{ |s| s.strip }`). `.reject(&:blank?)`
          # then drops any resulting empty/blank pieces, `.reject` keeps
          # only elements for which the block returns FALSE (the opposite of
          # `.select`), so this removes accidental blank entries (e.g. from
          # a stray double comma).
          street    = address_parts[0]
          city      = address_parts[1]
          state_zip = address_parts[2].to_s.split(/\s+/)
          # `.to_s` guards against `address_parts[2]` being `nil` (if there
          # were fewer than 3 comma-separated pieces). `.split(/\s+/)`
          # splits on one-or-more whitespace characters, turning "AZ 85296"
          # into ["AZ", "85296"].
          state     = state_zip[0]
          zip       = state_zip[1]

          phone = extract_phone(card)
          # Calls the private helper (defined near the bottom of this file)
          # that reads and formats the phone number for this card.

          next if street.blank?
          # `.blank?` is true for `nil`/empty/whitespace-only. `next` skips
          # the rest of THIS block iteration (this one card) and moves to
          # the next card, reached only when we couldn't even get a usable
          # street address.

          locations << {
            # `<<` appends a new Hash (one location) onto the `locations`
            # array.
            name:        "iStorage - #{street}",
            # iStorage's search results don't expose a distinct facility
            # "name" separate from its brand-qualified title/address, so we
            # build one by convention.
            address:     street,
            city:        city || "",
            # `||` falls back to an empty string if `city` came back `nil`.
            state:       state || "",
            zip:         zip || "",
            phone:       phone,
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
          log_warning("Error parsing iStorage card ##{idx + 1}: #{e.class}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue catches a `Playwright::TimeoutError` happening
      # anywhere else in the surrounding `begin` block (not already
      # swallowed by the `rescue nil` above).
      log_error("Timeout waiting for NSA Storage search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # This bare rescue comes AFTER the more specific one, since Ruby
      # checks `rescue` clauses top-to-bottom and uses the first match, so
      # this is the catch-all for anything else unexpected.
      log_error("Unexpected error parsing iStorage locations: #{e.class}: #{e.message}")
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
      page.wait_for_selector(".unit-select-item", timeout: 15_000)
      # Waits up to 15 seconds for at least one unit card to render. No
      # trailing `rescue nil` here, a timeout on a facility's own detail
      # page (which we already know exists, since parse_locations found it)
      # is treated as a real error, handled by the `rescue
      # Playwright::TimeoutError` clause further down.

      unit_els = page.query_selector_all(".unit-select-item")
      # Finds every unit card on this facility's detail page.

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.unit-select-item'. " \
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
          raw_size = safe_text(el, ".unit-select-item-detail-heading")
          # Reads the raw size heading text (e.g. "10 x 10") for this unit.
          size     = parse_size(raw_size)
          # Inherited helper: extracts the two numbers and normalizes them
          # to a "10x10"-style string, or `nil` on failure.
          next if size.blank?
          # Skip this unit if we couldn't determine a usable size.

          current_price = parse_price(safe_text(el, ".part_item_price"))
          # Reads and parses the currently-listed price (may be a promo
          # price or the regular price, depending on whether an old price is
          # also shown, decided below).
          old_price     = parse_price(safe_text(el, ".part_item_old_price"))
          # Reads and parses the higher, crossed-out "In-Store" price, if
          # present (`nil` if this unit has no promo).

          badges = safe_all_text(el, ".part_badge span")
          # Inherited helper: returns an Array of trimmed text for every
          # `<span>` inside a ".part_badge" element (e.g. ["1st Month
          # Free"]), or an empty Array if none found.

          monthly_price     = current_price
          web_special_price = nil
          web_special_note  = nil
          # Initialize all three to a default before deciding which values
          # actually apply, in the branches below.

          if old_price.present? && current_price.present? && old_price > current_price
            # `.present?` is true for non-nil/non-blank values. Only treat
            # this as a "web special" situation if BOTH prices exist AND the
            # old price is genuinely higher than the current one.
            monthly_price     = old_price
            # The higher, crossed-out price becomes the "regular" price.
            web_special_price = current_price
            # The lower, currently-listed price becomes the promotional
            # price.
            web_special_note  = badges.present? ? "Online price, #{badges.join(', ')}" : "Online price"
            # Ternary: if there were any promo badges, include them
            # (comma-joined) in the note; otherwise just say "Online price".
          elsif badges.present?
            # `elsif` = "else if", only checked if the first `if` condition
            # was false. Here: there was no old/current price gap, but there
            # WERE promo badges (e.g. a flat "1st Month Free" with no price
            # discount), still worth recording as a note.
            web_special_note = badges.join(", ")
          end
          # `end` closes the `if ... elsif ... end` branch.

          next if monthly_price.blank?
          # Skip this unit if we ended up with no usable price at all.

          features = safe_all_text(el, ".det-listing li span")
          # Array of trimmed feature-tag text, e.g. ["Drive Up Access",
          # "Outside"].
          feature_text = features.join(" | ").downcase
          # Joins every feature into one lower-cased string (separated by "
          # | ") so the substring checks below don't have to loop over the
          # array themselves.

          climate_controlled = feature_text.include?("heated and cooled") || feature_text.include?("climate")
          drive_up            = feature_text.include?("drive up")
          indoor               = feature_text.include?("inside") || (!drive_up && feature_text.include?("floor"))
          # `indoor` is true if the features explicitly say "inside", OR
          # (as a looser fallback) the unit isn't drive-up AND its features
          # mention a floor number (e.g. "1st Floor" implies an interior
          # unit).
          indoor               = !drive_up if features.empty?
          # A SECOND assignment to `indoor`, only applied `if features.empty?`
          #, i.e. this line only runs (overwriting the value computed just
          # above) when there was no feature text at all to go on, in which
          # case we fall back to the simplest possible guess: "indoor unless
          # we know it's drive-up." See the "flag but don't fix" notes at
          # the end of this review, reassigning the same variable twice
          # like this is a slightly unusual pattern worth double-checking.

          data_unit_size = el.get_attribute("data-unit-size").to_s
          # Reads the custom `data-unit-size` attribute (e.g. "small",
          # "vehicle"), `.to_s` guarding against `nil`.
          unit_type = data_unit_size == "vehicle" ? "vehicle" : "standard"
          # Ternary: "vehicle" only if that attribute exactly equals
          # "vehicle"; otherwise "standard".

          relative_booking_url = safe_attr(el, "a.form-opener", "href")
          # Inherited helper: reads the `href` of the booking-form-opener
          # link for this unit, or `nil`.
          booking_url = relative_booking_url.present? ? "#{BASE_URL}#{relative_booking_url}" : facility.facility_url
          # Ternary: build a full URL from the relative link if one was
          # found; otherwise fall back to the general facility page URL.

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price,
            web_special_note:   web_special_note,
            climate_controlled: climate_controlled,
            available:          true,
            # iStorage's listing doesn't expose per-unit "sold out" status
            # in what we scrape, so every parsed unit is assumed available.
            drive_up:           drive_up,
            indoor:             indoor,
            unit_type:          unit_type,
            booking_url:        booking_url
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

  # iStorage's (nsastorage.com's) search box takes a free-text "City, State"
  # query, not coordinates, reverse-geocode what we were given back into
  # that form. Same approach as Companies::PublicStorage.
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
      # Builds a "City, State" string, e.g. "Gilbert, Arizona", the last
      # expression of this branch, and (since the whole if/else is the
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

  # The phone link's text_content includes a leading sr-only "Call to speak
  # with a Storage Specialist at " label glued onto the number, so we read
  # the tel: href instead and format it.
  def extract_phone(card)
    href = safe_attr(card, "a[href^='tel:']", "href")
    # `a[href^='tel:']` matches an `<a>` whose `href` STARTS WITH "tel:"
    # (`^=` = "starts with"). Inherited `safe_attr` returns that link's
    # `href` value, or `nil` if no such link exists on this card.
    return nil if href.blank?
    # `.blank?` is true for `nil`/empty/whitespace-only. Nothing to format
    # if there's no phone link at all.

    digits = href.sub(/\Atel:/, "").gsub(/\D/, "")
    # `.sub(/\Atel:/, "")` removes a literal "tel:" prefix using a regex
    # anchored to the absolute start of the string (`\A`), replacing just
    # that FIRST match (`.sub` replaces only one occurrence, unlike
    # `.gsub`'s "replace all"). `.gsub(/\D/, "")` then removes every
    # non-digit character (`\D` is the regex shorthand for "NOT a digit"),
    # globally (all occurrences), leaving just the raw phone digits, e.g.
    # "4805551234".
    return nil if digits.length != 10
    # A US phone number should have exactly 10 digits (area code + number,
    # no country code), if it doesn't, treat it as unparseable rather than
    # showing a garbled number.

    "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}"
    # `digits[0, 3]` is Ruby's "String#[]" with a (start, length) pair,
    # takes 3 characters starting at index 0 (the area code); `digits[3, 3]`
    # takes the next 3 (the exchange); `digits[6, 4]` takes the final 4 (the
    # line number). String interpolation assembles them into the familiar
    # "(480) 555-1234" format. This is the method's last expression, so it's
    # the return value.
  end
  # `end` closes `def extract_phone`.
end
# `end` closes `class Companies::IStorage`.
