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

# NOVICE PRIMER: `class Companies::CubeSmart < Companies::BaseParser` defines
# this class as a SUBCLASS ("child class") of `Companies::BaseParser` (in
# base_parser.rb) — it INHERITS every method BaseParser defines (like `run`,
# `safe_text`, `safe_attr`, `parse_price`, `parse_size`, `log_info`,
# `log_warning`, `log_error`, `take_error_screenshot`) and only needs to
# implement the 4 methods unique to CubeSmart's website. "Playwright" is the
# browser-automation library: `page` objects below represent one open browser
# tab, and CSS-selector strings (like ".csStorageListing") are the same
# mini-language stylesheets use to target HTML elements — a leading `.` means
# "match this CSS class"; see base_parser.rb's opening comment for a fuller
# explanation of selectors, `query_selector`/`query_selector_all`, and Ruby's
# `protected`/`private` method visibility, since those apply here too.
class Companies::CubeSmart < Companies::BaseParser
  # A constant (ALL_CAPS name) holding CubeSmart's website root, reused below
  # when building absolute URLs out of relative "/foo" links found on the page.
  BASE_URL = "https://www.cubesmart.com"

  # Overrides BaseParser's abstract `company_name` — this is the required
  # display name shown in the UI/exports for this company.
  def company_name
    "CubeSmart"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug` — short id used in log
  # lines and screenshot filenames.
  def company_slug
    "cubesmart"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url` — builds the URL for
  # CubeSmart's search-results page given GPS coordinates and a radius.
  def search_url(lat, lng, radius_miles)
    # Stashed so parse_locations can filter results to the requested radius —
    # the search results page itself doesn't take a radius param, it just
    # returns whatever it considers "nearby" (seen up to ~20mi in testing).
    @radius_miles = radius_miles
    # `@radius_miles` (an instance variable, `@`-prefixed) is set here so
    # that `parse_locations` — a DIFFERENT method, called later by
    # BaseParser#run — can read it too. Instance variables are how separate
    # methods on the same object share state without passing extra
    # arguments around.

    zip = reverse_geocode_zip(lat, lng)
    # Calls the private helper defined near the bottom of this file, which
    # asks a geocoding service to translate GPS coordinates back into a
    # postal (ZIP) code.
    if zip.present?
      # `.present?` (Rails helper) is true when zip is a real, non-blank
      # value.
      "#{BASE_URL}/#{zip}-self-storage/"
      # String interpolation (`#{...}`) builds a URL like
      # "https://www.cubesmart.com/85296-self-storage/". Since this `if`
      # branch's last line is this string, and the whole `if/else` is the
      # last expression in the method, this string becomes `search_url`'s
      # return value when a zip was found.
    else
      location = reverse_geocode_city_state(lat, lng)
      # Fallback path when geocoding didn't return a ZIP: try to get a
      # city/state pair instead.
      if location
        # `location` here is either `nil` (geocoding totally failed) or a
        # Hash like `{ city: "Gilbert", state: "Arizona" }` (see the helper
        # method below) — a bare `if location` treats any non-nil/non-false
        # value as "truthy", so this branch runs whenever we got a real Hash
        # back.
        "#{BASE_URL}/#{location[:state].parameterize}-self-storage/#{location[:city].parameterize}-self-storage/"
        # `.parameterize` is a Rails String method that converts text into a
        # URL-safe "slug" — lowercasing it, replacing spaces/punctuation with
        # hyphens (e.g. "New York" -> "new-york"). Builds the second URL
        # form CubeSmart supports, e.g.
        # ".../arizona-self-storage/gilbert-self-storage/".
      else
        # Last-ditch fallback — unlikely to resolve, but keeps search_url
        # from raising if geocoding totally failed.
        "#{BASE_URL}/#{lat},#{lng}-self-storage/"
        # A URL built directly from the raw coordinates — almost certainly
        # won't match a real CubeSmart page, but guarantees `search_url`
        # always returns SOME string rather than crashing, so the crawl can
        # still fail gracefully (logging "no locations found") instead of
        # erroring out entirely.
      end
      # `end` closes the `if location ... else ... end` branch.
    end
    # `end` closes the outer `if zip.present? ... else ... end` branch.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations` — reads the list of
  # nearby CubeSmart facilities off the search-results page.
  def parse_locations(page)
    locations = []
    # Empty Array to collect one Hash per facility found.

    begin
      # NOTE: the visible "1 2 3" pager is purely client-side — every card is
      # already present in the DOM on first load, so .csStorageListing count
      # is a reliable "did we get real results" signal (unlike sites where a
      # hidden "no results" div is always present).
      page.wait_for_selector(".csStorageListing", timeout: 15_000) rescue nil
      # Waits up to 15 seconds for at least one facility card to appear.
      # The trailing `rescue nil` is Ruby's one-line rescue modifier: if
      # `wait_for_selector` raises ANY error (most likely a timeout because
      # this search location has zero results), that error is swallowed and
      # the whole expression evaluates to `nil` instead of crashing —
      # execution just continues to the next line, where `query_selector_all`
      # below will simply find zero cards and the "empty" branch handles it
      # cleanly.

      cards = page.query_selector_all(".csStorageListing")
      # Finds every facility-card element on the page (returns an empty
      # Array, not an error, if none match).

      if cards.empty?
        log_warning(
          "No facility cards found on CubeSmart search page (selector: '.csStorageListing'). " \
          "Run ReconService to check current page structure, or the search location may have " \
          "resolved to a 403/empty results page."
        )
        take_error_screenshot(page, "no_cards")
        return []
        # Exit early with an empty array — nothing to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} CubeSmart locations")

      cards.each_with_index do |card, idx|
        # Loops over every facility card, giving each a 0-based `idx`.
        begin
          link_el = card.query_selector("a[id$='-see-all-address']")
          # `a[id$='-see-all-address']` is an "attribute selector": it
          # matches `<a>` elements whose `id` attribute ENDS WITH
          # "-see-all-address" (`$=` means "ends with", as opposed to `^=`
          # which means "starts with"). Finds the link element carrying the
          # facility's address/detail-page info.
          rel_url = link_el&.get_attribute("href")
          # `&.` (safe navigation) calls `.get_attribute` only if `link_el`
          # isn't nil — avoids crashing if this particular card didn't have
          # that link for some reason.
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil
          # Ruby's ternary operator: `condition ? value_if_true :
          # value_if_false`. If `rel_url` is present (truthy), build a full
          # URL by prefixing `BASE_URL`; otherwise `url` is `nil`.

          external_id   = link_el&.get_attribute("facility")
          # Reads a custom `facility="<id>"` HTML attribute off the same
          # link element — CubeSmart's own internal ID for this location.
          distance_str  = link_el&.get_attribute("distance")
          # Reads a `distance="<miles>"` attribute — how far this facility
          # is from the searched point, as a string.
          distance_mi   = distance_str.presence&.to_f
          # `.presence` returns `distance_str` itself if it's non-blank, or
          # `nil` if it was blank/nil; `&.to_f` then safely converts it to a
          # Float only if it wasn't nil, giving us either a real number or
          # `nil` (never crashing on `nil.to_f`, though technically `nil.to_f`
          # doesn't crash in Ruby — it returns 0.0 — but chaining `&.` here
          # keeps a true "unknown distance" as `nil` rather than a
          # misleading 0.0).

          # Skip locations outside the requested radius — the site returns
          # whatever it considers "nearby" regardless of what we asked for.
          if @radius_miles.present? && distance_mi.present? && distance_mi > @radius_miles.to_f
            next
            # `next` skips the rest of this block iteration (this one card)
            # and moves to the next card in the loop — only reached when we
            # both know the radius the user asked for AND know this
            # facility's distance AND that distance exceeds what was asked.
          end
          # `end` closes this `if` check.

          address_lines = card.query_selector_all(".csFacilityLocation h3 span")
                              .map { |s| s.text_content&.strip }
                              .reject(&:blank?)
          # `.csFacilityLocation h3 span` (a "descendant selector", space
          # meaning "inside") matches every `<span>` inside an `<h3>` inside
          # an element with class "csFacilityLocation". `.map { |s| ... }`
          # converts each of those span elements into its trimmed text (or
          # nil if the span had no text). `.reject(&:blank?)` then removes
          # any nil/blank entries — `&:blank?` is shorthand for
          # `{ |x| x.blank? }`, and `.reject` keeps only the elements for
          # which the block returns FALSE (the opposite of `.select`). The
          # method call is split across 3 lines here purely for readability;
          # Ruby allows this because each line ends mid-expression (a
          # trailing `.` continues the chain).

          street         = address_lines[0]
          # Array indexing: the first captured text line, expected to be the
          # street address.
          city_state_zip = address_lines[1].to_s
          # The second line, expected to hold "City, ST 12345" together;
          # `.to_s` guards against `nil` (if there was no second line) by
          # converting it to an empty string so the `.split` calls below
          # don't crash.
          city           = city_state_zip.split(",").first&.strip
          # Splits on the comma, e.g. "Gilbert, AZ 85296" -> ["Gilbert", "
          # AZ 85296"], takes the first piece, and trims whitespace.
          state_zip      = city_state_zip.split(",").last.to_s.strip.split(/\s+/)
          # Takes the LAST piece from that same split (the "AZ 85296" part),
          # `.to_s` guards against nil again, `.strip` trims edge whitespace,
          # then `.split(/\s+/)` splits on one-or-more whitespace characters
          # (`\s+` is a regex meaning "one or more spaces/tabs") to separate
          # "AZ" from "85296" into an array like ["AZ", "85296"].
          state          = state_zip[0]
          zip            = state_zip[1]

          next if street.blank?
          # Skip this card entirely if we couldn't even get a street
          # address — not a usable location.

          locations << {
            # Appends a new Hash (one location) onto the `locations` array.
            name:        "CubeSmart - #{street}",
            # CubeSmart's search results don't include a distinct facility
            # "name" separate from its address, so we build one by
            # convention: "CubeSmart - <street>".
            address:     street,
            city:        city || "",
            state:       state || "",
            zip:         zip || "",
            phone:       nil,
            # No phone number is available from the search-results page for
            # CubeSmart (it's fetched later, per-facility, in parse_units
            # below).
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street} — #{city}, #{state}")
          # A checkmark-prefixed info log line for each successfully parsed
          # location, useful for eyeballing crawl progress in the logs.

        rescue => e
          # Catches any error while parsing THIS one card, so one bad card
          # doesn't stop the rest of the cards from being processed.
          log_warning("Error parsing CubeSmart card ##{idx + 1}: #{e.class}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # This would only trigger if something OTHER than the (already
      # rescued) `wait_for_selector` call timed out unexpectedly elsewhere in
      # this block.
      log_error("Timeout waiting for CubeSmart search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # Catch-all for any other unexpected error in the whole method.
      log_error("Unexpected error parsing CubeSmart locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # Return value: the array of location Hashes built above.
  end
  # `end` closes `def parse_locations`.

  # Overrides BaseParser's abstract `parse_units` — reads unit sizes/prices
  # off one facility's own detail page.
  def parse_units(page, facility)
    units = []
    # Empty Array to collect one Hash per unit found.

    begin
      page.wait_for_selector(".csUnitFacilityListing", timeout: 15_000)
      # Waits up to 15 seconds for the unit-listing container to render.
      # (No `rescue nil` here, unlike parse_locations — a timeout on THIS
      # page is treated as a real error, caught by the `rescue
      # Playwright::TimeoutError` clause further down, since a facility
      # detail page failing to render units is more unusual/worth flagging
      # than a search returning zero results.)

      # Facility-specific "Current Customers" number — the "New Customers"
      # number is a shared marketing/tracking line, not this store's line.
      phone = safe_text(page, ".csFacilityPhone a.new-phone:not(.new-customer)")
      # `:not(.new-customer)` is a CSS "negation pseudo-class" — it matches
      # elements that do NOT also have the "new-customer" class. So this
      # selector means "an <a class='new-phone'> inside .csFacilityPhone,
      # but only if it does NOT also have class 'new-customer'" — i.e. the
      # facility's own phone number, not the marketing "new customer" phone
      # line.
      if phone.blank?
        phone = safe_attr(page, ".csFacilityPhone a[href^='tel:']", "href")&.sub(/^tel:/, "")
        # Fallback: if the text-based lookup above found nothing, instead
        # read the `href` attribute of a phone link (`a[href^='tel:']`
        # matches a link whose href STARTS WITH "tel:"), then `.sub(/^tel:/,
        # "")` removes the "tel:" prefix using a regex (`^` anchors the
        # match to the start of the string) so we're left with just the
        # digits/formatted number. `&.` again guards against `phone` being
        # nil after `safe_attr`.
      end
      # `end` closes the `if phone.blank?` block.
      if phone.present? && facility.phone.blank?
        facility.update(phone: phone)
        # If we found a phone number here AND the Facility record doesn't
        # already have one saved, `.update` writes it to the database
        # immediately (a shortcut combining assigning the attribute and
        # saving in one call) — this is how a phone number discovered only
        # on the per-facility detail page ends up saved on the Facility even
        # though parse_locations (which ran earlier) had `phone: nil`.
      end
      # `end` closes the `if phone.present? && ...` block.

      unit_els = page.query_selector_all(".csUnitFacilityListing")
      # Finds every unit-listing element on this facility's page.

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: '.csUnitFacilityListing'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
      end
      # `end` closes the `if unit_els.empty?` block.

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          tab_group = el.get_attribute("data-tab-group").to_s
          # Reads a custom `data-tab-group` attribute (e.g. "Small",
          # "Parking") off this unit element, `.to_s` guarding against nil.

          raw_size = safe_text(el, ".csUnitColumn01 p span[aria-hidden]")
          # `span[aria-hidden]` matches a `<span>` that HAS an `aria-hidden`
          # attribute (any value) — commonly used to grab the
          # visually-displayed size text while ignoring a hidden
          # screen-reader-only duplicate elsewhere in the markup.
          size     = parse_size(raw_size)
          next if size.blank?
          # Skip this unit if we couldn't parse a valid size out of it.

          discount_text = safe_text(el, ".ptDiscountPriceSpan")
          original_text = safe_text(el, ".ptOriginalPriceSpan")
          # Reads the two possible price displays: a discounted ("online")
          # price and the original ("in-store") price.

          discount_price = parse_price(discount_text)
          original_price = parse_price(original_text)
          # `parse_price` (inherited) strips currency symbols/text and
          # converts to a Float, or nil if unparseable.

          monthly_price      = nil
          web_special_price  = nil
          web_special_note   = nil
          # Initialize all three to nil before deciding which values apply
          # below.

          if original_price.present? && discount_price.present? && original_price > discount_price
            monthly_price     = original_price
            web_special_price = discount_price
            web_special_note  = "Online price"
            # When BOTH prices exist and the original is genuinely higher,
            # treat the original as the "regular" monthly_price and the
            # lower one as the promotional web_special_price.
          else
            monthly_price = discount_price || original_price
            # Otherwise (only one price was found, or they're equal), just
            # use whichever price is available as the single monthly_price
            # — `||` falls back to `original_price` if `discount_price` is
            # nil.
          end
          # `end` closes the `if ... else ... end` branch.

          next if monthly_price.blank?
          # Skip this unit if we ended up with no usable price at all.

          features = el.query_selector_all(".csDisplayFeatures li").map { |li| li.text_content&.strip }.compact
          # Finds every `<li>` feature tag inside `.csDisplayFeatures`,
          # converts each to its trimmed text (or nil), then `.compact`
          # removes any nils — leaving a clean Array of feature strings like
          # "Climate Controlled", "Outside Drive-Up Access", etc.

          is_parking          = tab_group.casecmp?("parking")
          # `.casecmp?("parking")` is a case-INsensitive string comparison —
          # true if `tab_group` equals "parking" regardless of upper/lower
          # case (e.g. matches "Parking", "PARKING", "parking").
          drive_up            = features.any? { |f| f =~ /drive-up/i }
          # `.any? { |f| ... }` is true if the block returns truthy for AT
          # LEAST ONE element of `features`. `f =~ /drive-up/i` uses Ruby's
          # regex match operator `=~`: it returns the position where the
          # pattern matches (truthy) or `nil` if no match. `/drive-up/i` is
          # a regex literal matching the literal text "drive-up", with the
          # `i` flag making the match case-insensitive.
          climate_controlled  = features.any? { |f| f =~ /climate|heated|air cooled/i }
          # `|` inside a regex means "or" — matches if the feature text
          # contains "climate" OR "heated" OR "air cooled" (any case).
          indoor              = !is_parking && !drive_up
          # A unit counts as indoor only if it's neither a parking spot nor
          # a drive-up unit.

          unit_type = is_parking ? "parking" : "standard"
          # Ternary: "parking" if is_parking is true, otherwise "standard".

          reserve_path = safe_attr(el, "a.red-button", "href")
          # Reads the href of the "Reserve"-style button/link for this unit.
          booking_url  = reserve_path ? "#{BASE_URL}#{reserve_path}" : facility.facility_url
          # If a per-unit reserve link was found, build a full URL from it;
          # otherwise fall back to the general facility page URL.

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price,
            web_special_note:   web_special_note,
            climate_controlled: climate_controlled,
            available:          true,
            # CubeSmart's listing doesn't expose per-unit "sold out" status
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
      # `end` closes the `unit_els.each_with_index do |el, idx| ... end` loop.

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
  # Ruby's `private` keyword: everything defined below this line can only be
  # called from inside this class itself (not from outside code, and unlike
  # `protected`, not directly by a subclass calling it on another object
  # either — though since CubeSmart has no subclasses of its own here, the
  # practical effect is simply "these two helper methods are internal
  # implementation details of CubeSmart's own parsing logic, not part of the
  # class's public interface").

  # CubeSmart's search box (and its dedicated <zip>-self-storage/ URL) takes
  # a plain US zip code — reverse-geocode what we were given back into one.
  def reverse_geocode_zip(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    # `Geocoder` is a Ruby gem (third-party library) providing geocoding
    # (address <-> coordinates lookups). `.search([lat, lng])` performs a
    # "reverse geocode" — given coordinates, find the real-world address —
    # and returns an Array of possible matches; `.first` takes the top
    # (best) match, which could be `nil` if the service found nothing.
    result&.postal_code.presence
    # `&.postal_code` safely reads the ZIP code off the result only if
    # `result` isn't nil. `.presence` then converts a blank/empty ZIP into
    # `nil`, so callers get a clean "either a real zip, or nil" answer.
  rescue => e
    # A method-level rescue (attached directly to `def`, no separate
    # `begin` needed) — catches any error from the geocoding call (e.g. a
    # network failure) so a geocoding hiccup doesn't crash the whole crawl.
    log_warning("Reverse geocoding (zip) failed for #{lat},#{lng}: #{e.message}")
    nil
  end
  # `end` closes `def reverse_geocode_zip`.

  # Fallback for the rare case reverse geocoding doesn't yield a zip —
  # CubeSmart's alternate URL form takes a full state name + city name.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    return nil unless result&.city.present? && result&.state.present?
    # `unless` = "if not" — bails out with `nil` unless BOTH the city AND
    # state came back present from geocoding (using `&.` safe navigation in
    # case `result` itself is nil). `&&` requires both sides to be true.

    { city: result.city, state: result.state }
    # Builds and returns a small Hash with just the two fields `search_url`
    # needs — this is the last expression evaluated, so it's the method's
    # return value on success.
  rescue => e
    log_warning("Reverse geocoding (city/state) failed for #{lat},#{lng}: #{e.message}")
    nil
  end
  # `end` closes `def reverse_geocode_city_state`.
end
# `end` closes `class Companies::CubeSmart`.
