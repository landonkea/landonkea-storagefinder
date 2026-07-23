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

# NOVICE PRIMER: `class Companies::UHaul < Companies::BaseParser` makes this
# class a SUBCLASS ("child class") of `Companies::BaseParser` (see
# app/services/companies/base_parser.rb) — it INHERITS every method
# BaseParser defines (`run`, `safe_text`, `safe_attr`, `safe_all_text`,
# `parse_price`, `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`, etc.) and only needs to implement the 4 methods
# unique to U-Haul's own website. "Playwright" is the browser-automation
# library: a `page` object represents one open, invisible ("headless")
# browser tab, and CSS-selector strings (like "#storageResults li.divider")
# are the same mini-language stylesheets use to target HTML elements — a
# leading `#` means "match this element ID"; see base_parser.rb's opening
# comment for a fuller explanation of selectors and Ruby's
# `protected`/`private` keywords, both used here too.
class Companies::UHaul < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS name) holding U-Haul's website root, reused
  # below (implicitly, via string interpolation) when building absolute URLs.
  BASE_URL = "https://www.uhaul.com"

  # Overrides BaseParser's abstract `company_name` — required display name
  # shown in the UI/exports for this company.
  def company_name
    "U-Haul Self-Storage"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug` — short id used in log
  # lines and screenshot filenames.
  def company_slug
    "uhaul"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url` — builds the URL for
  # U-Haul's search-results page given GPS coordinates (radius_miles is
  # accepted for interface compatibility with BaseParser#run, but this site
  # has no radius parameter to pass it through to).
  def search_url(lat, lng, radius_miles)
    city, state = reverse_geocode_city_state(lat, lng)
    # "Multiple assignment": the private helper (defined near the bottom of
    # this file) returns a 2-element Array `[city, state]`; Ruby unpacks it
    # into two separate local variables in one line.
    slug = "#{city}-#{state}".gsub(/\s+/, "-")
    # String interpolation joins city and state with a literal hyphen (e.g.
    # "San Tan Valley-AZ"), then `.gsub(/\s+/, "-")` globally replaces every
    # run of one-or-more whitespace characters (`\s+`) with a single hyphen
    # — turning "San Tan Valley-AZ" into "San-Tan-Valley-AZ", matching the
    # hyphenated path segment U-Haul's own search box produces.
    "#{BASE_URL}/Storage/#{ERB::Util.url_encode(slug)}/Results/"
    # Builds the final URL. `ERB::Util.url_encode` percent-encodes the slug
    # so it's safe to embed in a URL path (guarding against any leftover
    # special characters), though by this point it should already be plain
    # hyphenated text. This is the method's last expression, so it's the
    # return value.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations` — reads the list of
  # nearby U-Haul facilities off the search-results page.
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per facility found.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block — code
      # inside `begin` runs normally; an error jumps to the matching
      # `rescue` clause instead of crashing this method.
      page.wait_for_selector("#storageResults li.divider", timeout: 15_000) rescue nil
      # `#storageResults li.divider` is a "descendant selector": any `<li
      # class="divider">` element found ANYWHERE inside the element with id
      # "storageResults". Waits up to 15 seconds (15,000ms) for at least one
      # to appear. The trailing `rescue nil` is Ruby's one-line rescue
      # modifier: any error here (most likely a timeout, if this city has
      # zero U-Haul facilities) is swallowed and the whole expression
      # becomes `nil` — execution simply continues to the next line, where
      # `query_selector_all` will find zero cards and the "empty" branch
      # below handles that cleanly.

      cards = page.query_selector_all("#storageResults li.divider")
      # Finds every facility-card element on the page — returns an empty
      # Array, never nil, if none match.

      if cards.empty?
        # `.empty?` is true for a zero-length Array.
        log_warning(
          "No facility cards found on U-Haul search results page " \
          "(selector: '#storageResults li.divider'). This may mean the searched " \
          "city/state genuinely has no nearby U-Haul locations, or the page " \
          "layout changed — run ReconService to check."
        )
        # The trailing `\` at each line's end continues the string literal
        # onto the next source line without a real newline — the pieces
        # concatenate into one message.
        take_error_screenshot(page, "no_cards")
        # Inherited helper: saves a screenshot of the current page to logs/,
        # tagged with this label, for later debugging.
        return []
        # Exits `parse_locations` immediately — nothing left to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} U-Haul locations")
      # `.length` on an Array returns how many elements it has.

      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` walks every element
        # of `cards`, running the block once per card, handing it to the
        # block as `card` and its 0-based position as `idx`.
        begin
          # Inner begin/rescue: an error parsing ONE card shouldn't stop the
          # rest of the cards from being processed.
          name_link = card.query_selector("h3 a")
          # Finds the `<a>` link inside this card's `<h3>` heading — a
          # descendant selector, "any `<a>` inside an `<h3>`".
          name      = name_link&.text_content&.strip
          # `&.` chains safe navigation: only reads `.text_content` (the
          # link's visible text) if `name_link` isn't `nil`, and only calls
          # `.strip` (trim whitespace) on that if it in turn isn't `nil`.
          url       = name_link&.get_attribute("href")&.strip
          # Same safe-navigation pattern, reading and trimming the link's
          # `href` attribute instead.

          next if name.blank? || url.blank?
          # `.blank?` (Rails helper) is true for `nil`/empty/whitespace-only.
          # `next` skips the rest of THIS block iteration (this one card)
          # and moves to the next card — reached when we couldn't get a
          # usable facility name OR URL (unlike some sibling parsers, this
          # check happens BEFORE parsing the address, since without a name
          # or URL there's nothing worth continuing to parse for this card).

          external_id = url[/\/(\d+)\/?\z/, 1]
          # `[...]` with a regex and capture-group index is Ruby's
          # "String#[]" pattern-match form: it searches `url` for
          # `/\/(\d+)\/?\z/` — a literal "/", a captured group of
          # one-or-more digits, an OPTIONAL trailing "/" (the `?` makes the
          # preceding "/" optional), anchored to the absolute end of the
          # string (`\z`) — and returns just the text captured by that
          # group (the trailing numeric facility ID), or `nil` if it
          # doesn't match.

          address_raw = safe_attr(card, "a.address-link", "rel")
          # Inherited helper: reads the `rel` HTML attribute (an unusual
          # place to stash address text, but that's where U-Haul puts it)
          # off the link with class "address-link" inside this card.

          street = nil
          city   = nil
          state  = nil
          zip    = nil
          # Initialize all four to `nil` up front, since parsing the raw
          # address text below is conditional (only attempted if
          # `address_raw` was actually found) and we still need these
          # variables to exist afterward either way.

          if address_raw.present?
            # `.present?` (Rails helper) is true for non-nil/non-blank
            # values — only attempt to parse the address if we actually got
            # some raw text back.
            # Format: "2557 S Gilbert Rd  Gilbert,AZ 85295" — street and
            # "City,State Zip" are separated by 2+ spaces, city/state by a
            # comma with no space.
            street_part, city_state_zip = address_raw.split(/\s{2,}/, 2)
            # "Multiple assignment" again: `.split(/\s{2,}/, 2)` splits the
            # raw text at the first run of 2-or-more whitespace characters
            # (`\s{2,}` — the `{2,}` quantifier means "2 or more, no upper
            # bound"), limited to at most 2 pieces (the trailing `2`
            # argument) so any extra double-spaces later in the string don't
            # cause additional splits.
            street = street_part&.strip
            # `&.` safely trims whitespace only if `street_part` isn't
            # `nil`.

            if city_state_zip.present?
              # Only continue parsing if the split actually produced a
              # second piece.
              city_part, state_zip = city_state_zip.split(",", 2)
              # Splits "Gilbert,AZ 85295" on its first comma (limited to 2
              # pieces) into ["Gilbert", "AZ 85295"].
              city = city_part&.strip

              if state_zip.present?
                state_zip_parts = state_zip.strip.split(/\s+/)
                # Trims the piece, then splits on one-or-more whitespace
                # characters, turning "AZ 85295" into ["AZ", "85295"].
                state = state_zip_parts[0]
                zip   = state_zip_parts[1]
              end
              # `end` closes the `if state_zip.present?` block.
            end
            # `end` closes the `if city_state_zip.present?` block.
          end
          # `end` closes the `if address_raw.present?` block.

          next if street.blank?
          # Skip this card entirely if, after all that parsing, we still
          # don't have a usable street address.

          locations << {
            # `<<` appends a new Hash (one location) onto the `locations`
            # array.
            name:        name,
            address:     street,
            city:        city || "",
            # `||` falls back to an empty string if `city` came back `nil`.
            state:       state || "AZ",
            # Falls back to the literal string "AZ" if no state was
            # scraped — see the "flag but don't fix" notes at the end of
            # this review regarding this hardcoded regional default.
            zip:         zip || "",
            phone:       nil,
            # No phone number is exposed on U-Haul's search-results cards in
            # what we scrape — left `nil`.
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{name} — #{street}, #{city}, #{state}")
          # A checkmark-prefixed info log line for each successfully parsed
          # location, useful for eyeballing crawl progress in the logs.

        rescue => e
          # A bare `rescue => e` (no exception class named) catches
          # `StandardError` and its subclasses, capturing the exception
          # object into local variable `e`.
          log_warning("Error parsing U-Haul card ##{idx + 1}: #{e.class}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue catches a `Playwright::TimeoutError` happening
      # anywhere else in the surrounding `begin` block (not already
      # swallowed by the `rescue nil` above).
      log_error("Timeout waiting for U-Haul search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # This bare rescue must come AFTER the more specific one — Ruby checks
      # `rescue` clauses top-to-bottom and uses the first match — so this is
      # the catch-all for anything else unexpected.
      log_error("Unexpected error parsing U-Haul locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # The last expression evaluated — the `locations` Array built above —
    # becomes `parse_locations`'s return value.
  end
  # `end` closes `def parse_locations`.

  # Overrides BaseParser's abstract `parse_units` — reads unit sizes/prices
  # off one facility's own detail page (the same URL parse_locations
  # discovered, re-visited by BaseParser#run's normal per-location flow —
  # see the header comment above).
  def parse_units(page, facility)
    units = []
    # Empty Array to collect one Hash per unit found.

    begin
      page.wait_for_selector("ul.uhjs-unit-list", timeout: 15_000)
      # Waits up to 15 seconds for at least one unit-list container to
      # render. No trailing `rescue nil` here — a timeout on a facility's
      # own detail page (which we already know exists) is treated as a real
      # error, handled by the `rescue Playwright::TimeoutError` clause
      # further down.

      room_lists = page.query_selector_all("ul.uhjs-unit-list")
      # Finds every unit-category container (`<ul class="uhjs-unit-list">`)
      # on this facility's detail page — each one groups units of one room
      # category together (e.g. all "Small Indoor" units in one list).

      if room_lists.empty?
        log_warning(
          "No unit room lists found at #{facility.name}. Selector: 'ul.uhjs-unit-list'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
        # Exits early with an empty array — nothing more to parse.
      end
      # `end` closes the `if room_lists.empty?` block.

      # The facility-wide "no admin fee" callout applies to every unit on
      # the page (U-Haul doesn't show a per-unit admin fee) — grab it once.
      admin_fee = page.content.include?("$0.00 Admin Fee") ? 0.0 : nil
      # `page.content` returns the ENTIRE raw HTML of the current page as
      # one big String (not scoped to any element) — a broad approach
      # compared to the targeted `query_selector` calls used everywhere
      # else in this file; see the "flag but don't fix" notes at the end of
      # this review. `.include?` checks whether that literal text appears
      # anywhere in the page. Ternary: if it's found, every unit's
      # `admin_fee` will be set to `0.0` (a real Float, meaning "confirmed
      # zero fee"); otherwise `nil` (meaning "unknown/not stated," which is
      # different from a confirmed $0).

      idx = 0
      # A plain counter (not tied to any one `.each_with_index`, since units
      # are nested two loops deep below — one over room_lists, one over each
      # list's own `<li>` items) used purely for numbering log messages.

      room_lists.each do |room_list|
        # `.each do |element| ... end` — no index needed here since `idx` is
        # tracked manually across BOTH loop levels instead.
        list_id    = room_list.get_attribute("id").to_s.downcase
        # Reads this list's `id` attribute (e.g.
        # "small_IndoorStorage_RoomList"), `.to_s` guards against `nil`,
        # `.downcase` lower-cases it for reliable case-insensitive matching
        # below.
        drive_up   = list_id.include?("driveup")
        # `.include?` checks whether the lower-cased id contains this
        # substring.
        vehicleish = list_id.match?(/vehicle|rv|boat|parking|outdoor/)
        # `.match?(regex)` returns `true`/`false` (unlike `.match`, which
        # returns a MatchData-or-nil) for whether the pattern matches
        # anywhere in the string. `|` inside a regex means "or" — matches if
        # the id contains any of these five words.
        indoor     = list_id.include?("indoor")

        unit_type =
          if vehicleish
            # Only figure out the specific vehicle-ish sub-type if
            # `vehicleish` was true at all.
            if list_id.include?("boat") then "boat"
            elsif list_id.include?("rv") then "rv"
            elsif list_id.include?("parking") then "parking"
            elsif list_id.include?("vehicle") then "vehicle"
            else "outdoor"
            end
            # `if ... then ... elsif ... then ... else ... end` written on
            # one line per branch using the `then` keyword (optional, but
            # required here since each condition and its result share a
            # line) — checks each vehicle-ish keyword in order and picks
            # the first one that matches; falls back to "outdoor" if the id
            # matched the broader `vehicleish` regex but none of these more
            # specific keywords individually.
          else
            "standard"
          end
        # `end` closes the outer `if vehicleish ... else ... end` expression
        # (note this `end` matches the OUTER if/else, since the inner
        # if/elsif/else/end above already closed itself on its own `end`
        # line just before this). The whole expression's result is assigned
        # to `unit_type`.

        room_list.query_selector_all("li").each do |el|
          # Within this one room_list, finds every `<li>` (one per
          # individual unit) and loops over them.
          idx += 1
          # `+=` is shorthand for `idx = idx + 1` — increments the shared
          # counter for every unit across every room_list, giving each a
          # unique, ever-increasing number for log messages.

          begin
            # Inner begin/rescue: an error parsing ONE unit shouldn't stop
            # the rest from being processed.
            raw_size = safe_text(el, "h4 span.nowrap") || safe_text(el, "h4")
            # Tries the more specific selector first (a `<span
            # class="nowrap">` inside the `<h4>`); `||` falls back to just
            # the `<h4>`'s own text if that more specific element wasn't
            # found.
            size     = parse_size(raw_size)
            # Inherited helper: extracts the two numbers and normalizes them
            # to a "10x10"-style string, or `nil` on failure.
            next if size.blank?
            # Skip this unit if we couldn't determine a usable size.

            price_texts   = safe_all_text(el, "dd b")
            # Inherited helper: an Array of trimmed text for every `<b>`
            # inside a `<dd>` element within this unit — U-Haul's markup may
            # list more than one bolded price-like value here.
            monthly_price = price_texts.map { |t| parse_price(t) }.compact.first
            # `.map { |t| ... }` runs `parse_price` on every text piece,
            # producing an Array where each entry is either a parsed Float
            # or `nil`. `.compact` removes the `nil` entries, leaving only
            # the successfully-parsed numbers. `.first` takes the first
            # (presumably the primary/relevant) price from what's left, or
            # `nil` if none parsed at all.

            features = safe_all_text(el, "ul.collapse.condensed li").map(&:downcase)
            # `.collapse.condensed` is TWO CSS classes chained with no space
            # between them, meaning "match an element that has BOTH classes
            # 'collapse' AND 'condensed'" (as opposed to a space, which
            # would mean "descendant of"). Reads every feature `<li>` inside
            # that list, lower-casing each (`&:downcase` is shorthand for
            # `{ |f| f.downcase }`).
            climate_controlled = features.any? { |f| f.include?("climate") }
            # `.any? { |f| ... }` is true if any feature string contains
            # "climate".

            units << {
              size:               size,
              monthly_price:      monthly_price,
              web_special_price:  nil,
              # Not exposed on U-Haul's unit markup in what we scrape — left
              # `nil`.
              web_special_note:   nil,
              admin_fee:          admin_fee,
              # The facility-wide value computed once, above, before this
              # loop started.
              insurance_note:     nil,
              # Not exposed on U-Haul's unit markup in what we scrape — left
              # `nil`.
              climate_controlled: climate_controlled,
              available:          true,
              # U-Haul's listing doesn't expose per-unit "sold out" status
              # in what we scrape, so every parsed unit is assumed
              # available.
              drive_up:           drive_up,
              indoor:             indoor && !drive_up,
              # A unit only counts as indoor if its room-list id said
              # "indoor" AND it isn't also flagged drive-up (some U-Haul
              # room-list ids can technically carry both signals at once).
              unit_type:          unit_type,
              booking_url:        facility.facility_url
              # U-Haul's unit markup doesn't carry a per-unit reservation
              # link — every unit just points back at the general facility
              # detail page.
            }

          rescue => e
            log_warning("Error parsing unit ##{idx} at #{facility.name}: #{e.message}")
          end
          # `end` closes the inner `begin ... rescue ... end` for one unit.
        end
        # `end` closes the `room_list.query_selector_all("li").each do |el| ... end`
        # loop over this room_list's individual units.
      end
      # `end` closes the `room_lists.each do |room_list| ... end` loop over
      # every unit-category container.

      if units.empty?
        # After both loops finish, check whether we ended up with zero
        # units overall even though the room-list CONTAINERS were present —
        # a different failure mode than `room_lists.empty?` above (that
        # earlier check meant no containers at all; this one means
        # containers existed but no individual `<li>` units inside them
        # parsed successfully).
        log_warning(
          "Unit room lists were present but no individual units parsed at " \
          "#{facility.name}. Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
      else
        # `else` here pairs with the `if units.empty?` above — runs when at
        # least one unit WAS successfully parsed.
        log_info("Found #{units.length} units at #{facility.name}")
      end
      # `end` closes the `if units.empty? ... else ... end` branch.

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
  # from outside code — these are internal implementation details.

  # U-Haul's search box takes a free-text "City, State" query, not
  # coordinates — reverse-geocode what we were given back into that form.
  # The URL also works fine with the full state name (e.g. "Gilbert-Arizona")
  # but we prefer the 2-letter abbreviation when Nominatim's ISO code is
  # available, to match what the site's own search box produces.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    # `Geocoder` is a third-party Ruby gem providing geocoding (address <->
    # coordinates lookups). `.search([lat, lng])` performs a "reverse
    # geocode" — coordinates in, real-world address out — returning an
    # Array of matches; `.first` takes the best one, which may be `nil`.
    if result&.city.present?
      # `&.` safely reads `.city` only if `result` isn't `nil`; `.present?`
      # is then true if that city string is real/non-blank.
      iso = result.data.dig("address", "ISO3166-2-lvl4")
      # `result.data` is the raw geocoding-service response as a nested Ruby
      # Hash. `.dig("address", "ISO3166-2-lvl4")` safely reaches two levels
      # deep — first the "address" key, then "ISO3166-2-lvl4" inside THAT —
      # returning `nil` at any point along the way if a key doesn't exist,
      # rather than raising an error the way chained `["address"]["ISO..."]`
      # bracket access would if "address" were missing. "ISO3166-2-lvl4" is
      # the geocoding service's field name for a region code like "US-AZ".
      state_abbr = iso&.split("-")&.last || result.state
      # `&.` safe-navigation chain: if `iso` isn't `nil`, `.split("-")`
      # breaks "US-AZ" into ["US", "AZ"], and `&.last` takes the last piece
      # ("AZ"). If `iso` was `nil` to begin with, the whole chain evaluates
      # to `nil`, and `||` then falls back to `result.state` (which may be a
      # full state name like "Arizona" rather than an abbreviation).
      [ result.city, state_abbr ]
      # Builds and returns a 2-element Array — this is the last expression
      # of this `if` branch, and (since the whole if/else is the method's
      # last expression) becomes the method's return value on success.
    else
      [ lat.to_s, lng.to_s ]
      # Fallback if geocoding failed entirely: returns the raw coordinates,
      # each explicitly converted to a String via `.to_s` (so the Array
      # always holds two Strings, matching the shape callers expect either
      # way). Won't match a real U-Haul city page, but guarantees the method
      # always returns something rather than crashing.
    end
    # `end` closes the `if result&.city.present? ... else ... end` branch.
  rescue => e
    # A method-level rescue (attached directly to `def`, no separate
    # `begin` needed) — catches any error from the geocoding call (e.g. a
    # network failure).
    log_warning("Reverse geocoding failed for #{lat},#{lng}: #{e.message}")
    [ lat.to_s, lng.to_s ]
    # Same raw-coordinates fallback as the `else` branch above.
  end
  # `end` closes `def reverse_geocode_city_state`.
end
# `end` closes `class Companies::UHaul`.
