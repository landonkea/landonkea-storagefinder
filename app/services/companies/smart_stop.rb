# =============================================================================
# SMARTSTOP SELF STORAGE PARSER
# =============================================================================
# Crawls smartstopselfstorage.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site, see recon/ for
# saved HTML/screenshots, and the ad-hoc scripts used to discover this):
#   - No bot-detection/CAPTCHA challenge was ever encountered on this site
#     while doing this research (no Cloudflare/PerimeterX challenge page, no
#     "press & hold" gate, the "Protected by Cloudflare" footer badge is
#     just a static trust badge, not an active challenge).
#   - The search page takes real lat/lng query params directly:
#       /find-storage?latitude=<lat>&longitude=<lng>
#     (Confirmed by driving the on-page location-search box, which is a
#     Google Places Autocomplete widget, selecting/submitting a place
#     navigates the browser to exactly this URL shape.)
#   - The site does NOT expose a radius query param, it always searches a
#     fixed 25-mile radius regardless of what's passed, so `radius_miles`
#     is accepted for interface compatibility but not used.
#   - Search results render server-side as `.location-card` elements, each
#     with a link (`.location-card__buttons a`) to that facility's detail
#     page at /find-storage/<state>/<city>/<slug>?unitSize=all, visiting
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

# NOVICE PRIMER: `class Companies::SmartStop < Companies::BaseParser` makes
# this class a SUBCLASS ("child class") of `Companies::BaseParser` (see
# app/services/companies/base_parser.rb), it INHERITS every method
# BaseParser defines (`run`, `safe_text`, `safe_attr`, `safe_all_text`,
# `parse_price`, `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`, etc.) and only needs to implement the 4 methods
# unique to SmartStop's own website. "Playwright" is the browser-automation
# library: a `page` object represents one open, invisible ("headless")
# browser tab, and CSS-selector strings (like ".location-card") are the same
# mini-language stylesheets use to target HTML elements, see
# base_parser.rb's opening comment for a fuller explanation of selectors and
# Ruby's `protected`/`private` keywords, both used here too.
class Companies::SmartStop < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS name) holding SmartStop's website root,
  # reused below when building absolute URLs from relative "/foo" links.
  BASE_URL = "https://www.smartstopselfstorage.com"

  # Overrides BaseParser's abstract `company_name`, required display name
  # shown in the UI/exports for this company.
  def company_name
    "SmartStop"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug`, short id used in log
  # lines and screenshot filenames.
  def company_slug
    "smartstop"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url`, builds the URL for
  # SmartStop's search-results page given GPS coordinates and a radius.
  def search_url(lat, lng, radius_miles)
    # SmartStop's search endpoint takes real lat/lng directly, no
    # reverse-geocoding needed. radius_miles is unused: the site has no
    # radius param and always searches a fixed 25-mile radius.
    "#{BASE_URL}/find-storage?latitude=#{lat}&longitude=#{lng}"
    # String interpolation (`#{...}`) builds the URL by inserting `lat` and
    # `lng` directly into the query string. Note `radius_miles` (the third
    # method parameter) is never referenced in the body, per the comment
    # above, this is intentional, not an oversight; kept as a parameter only
    # so this method matches the abstract signature BaseParser#run expects
    # from every subclass. This is the method's only expression, so it's the
    # return value.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations`, reads the list of
  # nearby SmartStop facilities off the search-results page.
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per facility found.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block, code
      # inside `begin` runs normally; an error jumps to the matching
      # `rescue` clause instead of crashing this method.
      page.wait_for_selector(".location-card", timeout: 15_000) rescue nil
      # Waits up to 15 seconds (15,000ms) for at least one facility card to
      # appear. The trailing `rescue nil` is Ruby's one-line rescue
      # modifier: any error here (most likely a timeout, if this search area
      # has zero results) is swallowed and the whole expression becomes
      # `nil`, execution simply continues to the next line, where
      # `query_selector_all` will find zero cards and the "empty" branch
      # below handles that cleanly.

      cards = page.query_selector_all(".location-card")
      # Finds every facility-card element on the page, returns an empty
      # Array, never nil, if none match.

      if cards.empty?
        # `.empty?` is true for a zero-length Array.
        log_warning(
          "No facility cards found on SmartStop search page (selector: '.location-card'). " \
          "Run ReconService to check current page structure."
        )
        # The trailing `\` continues the string literal onto the next
        # source line without a real newline, the pieces concatenate into
        # one message.
        take_error_screenshot(page, "no_cards")
        # Inherited helper: saves a screenshot of the current page to logs/,
        # tagged with this label, for later debugging.
        return []
        # Exits `parse_locations` immediately, nothing left to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} SmartStop locations")
      # `.length` on an Array returns how many elements it has.

      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` walks every element
        # of `cards`, running the block once per card, handing it to the
        # block as `card` and its 0-based position as `idx`.
        begin
          # Inner begin/rescue: an error parsing ONE card shouldn't stop the
          # rest of the cards from being processed.
          link    = card.query_selector(".location-card__buttons a")
          # Finds the facility-detail link (a descendant selector: any
          # `<a>` inside an element with class "location-card__buttons")
          # inside this card.
          rel_url = link&.get_attribute("href")
          # `&.` safely reads the `href` attribute only if `link` isn't
          # `nil`.
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil
          # Ruby's ternary operator: builds a full absolute URL if a
          # relative one was found; otherwise `url` is `nil`.

          street            = safe_text(card, ".location-card__address1")
          # Inherited helper: reads the trimmed text of the first-address-
          # line element, or `nil` if not found.
          city_state_zip    = safe_text(card, ".location-card__address2")
          # Reads the combined "City, ST 12345" second address line.
          city, state, zip  = parse_city_state_zip(city_state_zip)
          # "Multiple assignment": calls the private helper (defined near
          # the bottom of this file), which returns a 3-element Array, and
          # Ruby unpacks it into three separate local variables in one line
          # , equivalent to writing `parts = parse_city_state_zip(...);
          # city = parts[0]; state = parts[1]; zip = parts[2]` by hand.

          next if street.blank?
          # `.blank?` (Rails helper) is true for `nil`/empty/whitespace-only.
          # `next` skips the rest of THIS block iteration (this one card)
          # and moves to the next card, reached when we couldn't even get a
          # usable street address.

          # The URL slug (e.g. "/find-storage/az/phoenix/1500-e-baseline-rd")
          # is stable per facility and unique, use it as external_id since
          # the search results page doesn't expose a numeric store ID.
          external_id = rel_url&.split("?")&.first
          # `&.` safe-navigation chain: if `rel_url` isn't `nil`,
          # `.split("?")` breaks it at the "?" that starts the query string
          # (e.g. "?unitSize=all"), producing an Array like
          # ["/find-storage/az/phoenix/1500-e-baseline-rd"]; `&.first` then
          # safely takes the first piece (the path without any query
          # string), the whole chain evaluates to `nil` if `rel_url` itself
          # was `nil`.

          locations << {
            # `<<` appends a new Hash (one location) onto the `locations`
            # array.
            name:        "SmartStop Self Storage - #{street}",
            # SmartStop's search results don't include a distinct facility
            # "name" separate from its address, so we build one by
            # convention: "SmartStop Self Storage - <street>".
            address:     street,
            city:        city || "",
            # `||` falls back to an empty string if `city` came back `nil`.
            state:       state || "",
            zip:         zip || "",
            phone:       nil,
            # No phone number is exposed on SmartStop's search-results cards
            # in what we scrape, left `nil`.
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
          log_warning("Error parsing SmartStop card ##{idx + 1}: #{e.class}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue catches a `Playwright::TimeoutError` happening
      # anywhere else in the surrounding `begin` block (not already
      # swallowed by the `rescue nil` above).
      log_error("Timeout waiting for SmartStop search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # This bare rescue must come AFTER the more specific one, Ruby checks
      # `rescue` clauses top-to-bottom and uses the first match, so this is
      # the catch-all for anything else unexpected.
      log_error("Unexpected error parsing SmartStop locations: #{e.class}: #{e.message}")
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
      page.wait_for_selector(".unit-card", timeout: 15_000)
      # Waits up to 15 seconds for at least one unit card to render. No
      # trailing `rescue nil` here, a timeout on a facility's own detail
      # page (which we already know exists) is treated as a real error,
      # handled by the `rescue Playwright::TimeoutError` clause further
      # down.

      cards = page.query_selector_all(".unit-card")
      # Finds every unit card on this facility's detail page.

      if cards.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.unit-card'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
        # Exits early with an empty array, nothing more to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} units at #{facility.name}")

      cards.each_with_index do |card, idx|
        begin
          raw_size = safe_text(card, ".unit-card__size__dimension")
          # Reads the raw size text (e.g. "10' x 10'") for this unit.
          size     = parse_size(raw_size)
          # Inherited helper: extracts the two numbers and normalizes them
          # to a "10x10"-style string, or `nil` on failure.
          next if size.blank?
          # Skip this unit if we couldn't determine a usable size.

          features = safe_all_text(card, ".unit-card__features__list li").map(&:downcase)
          # Inherited helper: an Array of trimmed text for every `<li>`
          # feature tag; `.map(&:downcase)` then lower-cases every entry
          # (`&:downcase` is shorthand for `{ |f| f.downcase }`) so the
          # substring checks below are case-insensitive.

          climate_controlled = features.any? { |f| f.include?("climate") }
          # `.any? { |f| ... }` is true if the block returns truthy for AT
          # LEAST ONE feature string, here, any feature containing
          # "climate".
          drive_up           = features.any? { |f| f.include?("drive-up") }
          outdoor             = features.any? { |f| f.include?("outside") || f.include?("outdoor") }
          indoor              = !outdoor
          # A unit counts as indoor simply if it's not tagged outdoor/
          # outside, for this company.
          is_vehicle          = features.any? { |f| f.include?("vehicle") || f.include?("rv") || f.include?("boat") }
          unit_type           = is_vehicle ? "vehicle" : "standard"
          # Ternary: "vehicle" if any vehicle-ish feature keyword was found;
          # otherwise "standard".

          in_store_price = parse_price(safe_text(card, ".unit-card__cost__store__value"))
          # Reads and parses the crossed-out "In-Store" price, if present.
          promo_price    = parse_price(safe_text(card, ".unit-card__cost__web__value"))
          # Reads and parses the "Promo Rate" price, if present.

          # In-store (crossed-out) price is the "regular" price; the lower
          # promo price (when present) is the web special.
          monthly_price      = in_store_price || promo_price
          # `||` falls back to `promo_price` if `in_store_price` is `nil`
          # (e.g. a unit with no promo at all, only one price shown).
          web_special_price  = nil
          web_special_note   = nil
          admin_fee          = nil
          # Initialize all three to `nil` before deciding whether a promo
          # situation applies, below.

          if promo_price.present? && in_store_price.present? && promo_price < in_store_price
            # `.present?` is true for non-nil/non-blank values. Only treat
            # this as a real "web special" if BOTH prices exist AND the
            # promo price is genuinely lower.
            web_special_price = promo_price

            badge_text = safe_text(card, ".unit-card__cost__badges__promo .badge")
            # Reads the promo badge's full text, which may bundle multiple
            # pieces of information together (see comment below).
            if badge_text.present?
              # Badge text concatenates the headline with a hidden
              # tooltip's detail rows, e.g. "1st Month Rent Free *Move-In
              # CostsOne-Time Admin Fee$29.00...". Split off just the
              # headline.
              web_special_note = badge_text.split(/Move-In Costs/i).first.to_s.strip.presence
              # `.split(regex)` breaks the string at every place matching
              # `/Move-In Costs/i` (the `i` flag makes it case-insensitive)
              # , `.first` takes the piece BEFORE that marker (the actual
              # promo headline), `.to_s` guards against `nil` if the split
              # produced nothing, `.strip` trims whitespace, and `.presence`
              # (Rails helper) converts an empty result to `nil` rather than
              # keeping an empty string.

              if (m = badge_text.match(/Admin Fee\$?([\d.]+)/i))
                # `badge_text.match(regex)` returns a `MatchData` object (or
                # `nil`) for the pattern "Admin Fee" followed by an optional
                # "$" and a captured group of digits/decimal point. Wrapping
                # the assignment `m = ...` in parentheses and using it
                # directly as the `if` condition is a common Ruby idiom:
                # `if` treats a non-nil `MatchData` as truthy, so this block
                # only runs when the pattern actually matched, AND `m` is
                # available inside the block referring to that match.
                admin_fee = parse_price(m[1])
                # `m[1]` reads the text captured by the first parenthesized
                # group (the fee digits) out of the match; `parse_price`
                # (inherited) converts that to a Float.
              end
              # `end` closes the `if (m = badge_text.match(...))` block.
            end
            # `end` closes the `if badge_text.present?` block.

            web_special_note ||= safe_text(card, ".unit-card__cost__web__online-rate")
            # `||=` is Ruby's "assign only if currently nil/false" operator
            # , only runs the right-hand `safe_text` lookup and reassigns
            # `web_special_note` if it's still `nil` at this point (i.e. the
            # badge text above didn't produce a usable note), giving a
            # second chance to find promo text from a different element.
          end
          # `end` closes the outer `if promo_price.present? && ...` block.

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price,
            web_special_note:   web_special_note,
            admin_fee:          admin_fee,
            insurance_note:     nil,
            # Not exposed on SmartStop's unit markup in what we scrape,
            # left `nil`.
            climate_controlled: climate_controlled,
            available:          true,
            # SmartStop's listing doesn't expose per-unit "sold out" status
            # in what we scrape, so every parsed unit is assumed available.
            drive_up:           drive_up,
            indoor:             indoor,
            unit_type:          unit_type,
            booking_url:        facility.facility_url
            # SmartStop's unit markup doesn't carry a per-unit reservation
            # link, every unit just points back at the general facility
            # detail page.
          }

        rescue => e
          log_warning("Error parsing unit ##{idx + 1} at #{facility.name}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one unit.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end`
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

  # Parses "Phoenix, AZ 85042" (or "Phoenix , AZ 85042", extra space seen
  # in the wild) into [city, state, zip].
  def parse_city_state_zip(text)
    return [ nil, nil, nil ] if text.blank?
    # `.blank?` is true for `nil`/empty/whitespace-only, nothing to parse
    # if there's no text at all. Returns a 3-element Array of `nil`s so
    # callers can always safely destructure the result into three
    # variables, whether or not parsing succeeded.

    match = text.match(/^(.+?)\s*,\s*([A-Za-z]{2})\s+(\d{5})/)
    # `.match(regex)` searches for the first place this pattern matches,
    # returning a `MatchData` object or `nil`. The pattern breaks down as:
    # `^` anchors to the start of the string; `(.+?)` is a "non-greedy"
    # capture group matching one-or-more of any character, but as FEW as
    # possible (so it stops at the first comma rather than swallowing too
    # much), this captures the city name; `\s*,\s*` matches a comma with
    # optional whitespace on either side; `([A-Za-z]{2})` captures exactly 2
    # letters (the state abbreviation); `\s+` matches one-or-more spaces;
    # `(\d{5})` captures exactly 5 digits (the ZIP code).
    return [ nil, nil, nil ] unless match
    # `unless` = "if not". Bails out with all-nil if the text didn't match
    # the expected "City, ST 12345" shape at all.

    [ match[1].strip, match[2].strip.upcase, match[3].strip ]
    # Builds and returns the final 3-element Array: `match[1]` is the city
    # (captured group 1, trimmed of any stray whitespace); `match[2]` is the
    # state (captured group 2, trimmed and `.upcase`d for consistency, e.g.
    # "az" -> "AZ"); `match[3]` is the ZIP (captured group 3, trimmed). This
    # is the method's last expression, so it's the return value.
  end
  # `end` closes `def parse_city_state_zip`.
end
# `end` closes `class Companies::SmartStop`.
