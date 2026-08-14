# =============================================================================
# STORAMERICA PARSER
# =============================================================================
# Crawls what the stub called "storamerica.com" to find facilities and unit
# pricing.
#
# Confirmed live against the real site on 2026-08-11 (Chrome DevTools,
# inspecting rendered markup directly, not just an HTTP fetch of the raw
# HTML):
#   - storamerica.com 301-redirects to www.sroa.com. The StorAmerica brand
#     now operates under the name "Storage Rentals of America" (SROA) at
#     that domain. BASE_URL below points at sroa.com directly so every
#     crawl request lands on the real site instead of eating a redirect hop
#     each time. We keep "StorAmerica" as company_name/company_slug and the
#     registry key unchanged, that's the name already baked into this app's
#     CompanyRegistry entry, dashboard labels, and Facility fixtures, only
#     the underlying domain moved.
#   - Search is a two-level path: /find-storage/<state>/<city>, full state
#     and city names, lowercase, dash-separated (e.g.
#     /find-storage/florida/miami), NOT two-letter abbreviations (unlike
#     Companies::SmartStop's /find-storage/<state-abbr>/<city>/<slug> shape,
#     a different site with a similarly-worded URL). Confirmed against
#     /find-storage/florida/miami (2 real facilities returned). SROA does
#     NOT operate in every state, an unsupported state (confirmed: Arizona)
#     renders a "storage isn't available in your selected area" message
#     instead of 404ing, parse_locations below treats that the same as any
#     other zero-results page.
#   - Known limitation: some cities that exist in multiple states use a
#     disambiguated slug instead of the plain city name (e.g. Columbus, OH
#     is linked as /find-storage/ohio/columbus-oh, not .../columbus).
#     reverse_geocode_city_state/slugify below can't predict this, so a
#     search for one of those ambiguous cities may 404 or return zero
#     results even where SROA has a real facility. Not solved here, no
#     other parser in this codebase handles per-city slug exceptions
#     either.
#   - Facility detail pages are /find-storage/<state>/<city>/<facility-slug>
#     (e.g. .../florida/miami/sunnybrook-miami), confirmed by following a
#     real facility card's link.
#   - The site is a Tailwind + Ant Design React app. Tailwind utility class
#     strings (the "w-full flex flex-col gap-4" style names below) are
#     real, confirmed selectors as of this date, but are inherently more
#     fragile than semantic class names since they can shift with any
#     styling tweak. Where a stable alternative existed, this parser uses
#     it instead: Ant Design's own fixed component classes (e.g.
#     "ant-list-items" for the unit list) don't come from Tailwind and are
#     far less likely to change on a routine style pass.
#   - The location results list can share its Tailwind class combo with an
#     unrelated "Similar Storage Locations" carousel further down some
#     pages (confirmed on the Sunnybrook facility page). Calling
#     `query_selector` (singular, returns the FIRST match) instead of
#     `query_selector_all` on the list container is what keeps this parser
#     scoped to the real results and out of that carousel.
#
# If the site layout changes and this parser breaks, re-run this same
# manual inspection (Chrome DevTools against a real find-storage page) and
# update the selectors below, or use ReconService if it's been extended to
# support JS-rendered SPAs by then.
# =============================================================================

# NOVICE PRIMER: `class Companies::StorAmerica < Companies::BaseParser` makes
# this class a SUBCLASS ("child class") of `Companies::BaseParser` (see
# app/services/companies/base_parser.rb), it INHERITS every method
# BaseParser defines (`run`, `safe_text`, `safe_attr`, `safe_all_text`,
# `parse_price`, `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`, etc.) and only needs to implement the 4 methods
# unique to this company's own website. "Playwright" is the browser-
# automation library: a `page` object represents one open, invisible
# ("headless") browser tab, and CSS-selector strings (like ".ant-list-items")
# are the same mini-language stylesheets use to target HTML elements, see
# base_parser.rb's opening comment for a fuller explanation of selectors and
# Ruby's `protected`/`private` keywords, both used here too.
class Companies::StorAmerica < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS name) holding the confirmed real domain this
  # brand now serves from (see header comment above), reused below when
  # turning relative "/foo" links found on the page into full absolute URLs.
  BASE_URL = "https://www.sroa.com"

  # Overrides BaseParser's abstract `company_name`, the required display
  # name shown in the UI/exports for this company. Kept as "StorAmerica"
  # (not the site's current "Storage Rentals of America" branding) to match
  # the existing CompanyRegistry key, dashboard labels, and Facility
  # fixtures already built around that name.
  def company_name
    "StorAmerica"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug`, short id used in log
  # lines and screenshot filenames.
  def company_slug
    "storamerica"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url`, builds the URL for this
  # company's search-results page given GPS coordinates. The site's search
  # is path-based (state name, then city name) rather than a lat/lng or zip
  # query param, so we reverse-geocode what we're given into a "City, State"
  # pair first, same pattern as Companies::DevonSelfStorage/PublicStorage/
  # UHaul. `radius_miles` is accepted for interface compatibility with
  # BaseParser#run but unused, no radius param was found in the confirmed
  # URL shapes (see header comment).
  def search_url(lat, lng, radius_miles)
    city, state = reverse_geocode_city_state(lat, lng)
    "#{BASE_URL}/find-storage/#{slugify(state)}/#{slugify(city)}"
    # String interpolation builds a URL like
    # "https://www.sroa.com/find-storage/florida/miami". This is the
    # method's last expression, so it's the return value.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations`, reads the list of
  # nearby facilities off the search-results page. Selectors confirmed
  # live against /find-storage/florida/miami (see header comment).
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per facility found.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block, code
      # inside `begin` runs normally; an error jumps to the matching
      # `rescue` clause instead of crashing this method.
      page.wait_for_selector(".w-full.flex.flex-col.gap-4 h3", timeout: 15_000) rescue nil
      # Waits up to 15 seconds (15,000ms) for at least one facility card's
      # name heading to appear. The trailing `rescue nil` is Ruby's one-line
      # rescue modifier: any error here (most likely a timeout, if this
      # search area has zero results, e.g. a state SROA doesn't serve, see
      # header comment) is swallowed and the whole expression becomes
      # `nil`, execution continues to the next line.

      # IMPORTANT: `query_selector` (singular) here, not `query_selector_all`.
      # This class combo can also match an unrelated "Similar Storage
      # Locations" carousel further down some pages (confirmed on facility
      # detail pages, not confirmed on the search-results page itself, but
      # not worth risking). `query_selector` returns only the FIRST match,
      # which is confirmed to always be the real results list.
      list_container = page.query_selector(".w-full.flex.flex-col.gap-4")

      if list_container.nil?
        log_info("No StorAmerica results container found (likely a state/city SROA doesn't serve)")
        return []
      end
      # `end` closes the `if list_container.nil?` block.

      cards = list_container.query_selector_all("li")
      # Finds every facility-card `<li>` inside the (correctly scoped)
      # results list. Returns an empty Array, never nil, if none match.

      if cards.empty?
        log_warning(
          "No facility cards found on StorAmerica search page " \
          "(container '.w-full.flex.flex-col.gap-4' found, but no <li> " \
          "children). Site markup may have changed, see this file's " \
          "header comment for how these selectors were confirmed."
        )
        take_error_screenshot(page, "no_cards")
        return []
        # Exits `parse_locations` immediately, nothing left to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} StorAmerica locations")
      # `.length` on an Array returns how many elements it has.

      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` walks every
        # element of `cards`, running the block once per card, handing it
        # to the block as `card` and its 0-based position as `idx`.
        begin
          # Inner begin/rescue: an error parsing ONE card shouldn't stop
          # the rest of the cards from being processed.
          name = safe_text(card, "h3")
          # The facility name is the card's only `<h3>`, confirmed live
          # (e.g. "Sunnybrook").

          # Distance ("N miles away") and street address are the two
          # `<span>`s inside the card's address block, in that fixed order,
          # confirmed live. There's no more specific stable selector for
          # either individually (both are inside the same
          # "flex flex-col gap-1" wrapper with no distinguishing class), so
          # we grab both spans positionally and split them by index.
          address_spans = card.query_selector_all(".flex.flex-col.gap-1 span")
          address = address_spans[1]&.text_content&.strip
          # `&.` is Ruby's "safe navigation operator", calls the next method
          # only if the left side isn't nil, so a missing second span just
          # gives `nil` instead of raising. `address_spans[0]` would be the
          # distance text ("N miles away"), not captured, Facility doesn't
          # have a field for it and BaseParser recomputes distance from
          # lat/lng anyway.

          phone = safe_text(card, "a[href^='tel:']")
          # Confirmed live: the phone number is the only `tel:` link in the
          # card.

          url = safe_attr(card, "a[href*='/find-storage/']", "href")
          # Confirmed live: the facility detail link
          # (/find-storage/<state>/<city>/<facility-slug>) is the only
          # link matching this pattern inside the card (the phone link
          # doesn't match it, it's a tel: link).
          url = "#{BASE_URL}#{url}" if url&.start_with?("/")
          # If the href was a site-relative path (starting with "/"),
          # prefix it with `BASE_URL` to make it a full absolute URL;
          # otherwise leave it as-is.

          next if name.blank? || address.blank?
          # `.blank?` (Rails helper) is true for nil, empty, or whitespace-
          # only strings. `next` skips the rest of THIS block iteration and
          # moves to the next card, without a real name AND address this
          # "location" isn't usable.

          locations << {
            # `<<` appends a new Hash (one location) onto the `locations`
            # array.
            name:        name,
            address:     address,
            city:        "",
            state:       "",
            zip:         "",
            # City/state/zip aren't broken out separately in the card, only
            # a single combined address string was confirmed (e.g. "1020
            # Sunnybrook Road, Miami, FL 33136"). Left blank rather than
            # guessing a regex split, BaseParser#upsert_facility falls back
            # to matching on company + address either way (see below).
            phone:       phone,
            url:         url,
            external_id: nil
            # No stable per-location ID was confirmed on this site, so
            # Facility upsert falls back to matching on company + address
            # (see BaseParser#upsert_facility), same as any company whose
            # site doesn't expose one.
          }

          log_info("  ✓ #{name}: #{address}")
          # A checkmark-prefixed info log line for each successfully parsed
          # location, useful for eyeballing crawl progress in the logs.

        rescue => e
          # A bare `rescue => e` (no exception class named) catches
          # `StandardError` and its subclasses, i.e. "any ordinary error",
          # capturing the exception object into local variable `e`.
          log_warning("Error parsing StorAmerica card ##{idx + 1}: #{e.class}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue catches a `Playwright::TimeoutError` happening
      # anywhere else in the surrounding `begin` block (not already
      # swallowed by the `rescue nil` above).
      log_error("Timeout waiting for StorAmerica search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # This bare rescue must come AFTER the more specific one, Ruby checks
      # `rescue` clauses top-to-bottom and uses the first match, so this is
      # the catch-all for anything else unexpected.
      log_error("Unexpected error parsing StorAmerica locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # The last expression evaluated, the `locations` Array built above,
    # becomes `parse_locations`'s return value.
  end
  # `end` closes `def parse_locations`.

  # Overrides BaseParser's abstract `parse_units`, reads unit sizes/prices
  # off one facility's own detail page. Selectors confirmed live against
  # /find-storage/florida/miami/sunnybrook-miami (see header comment).
  def parse_units(page, facility)
    units = []
    # Empty Array to collect one Hash per unit found.

    begin
      page.wait_for_selector(".ant-list-items", timeout: 15_000)
      # Waits up to 15 seconds for the unit list to render. `ant-list-items`
      # is Ant Design's own fixed class for a List component's item
      # container, confirmed live, not a Tailwind utility string, so it's
      # unlikely to change on a routine style pass. No trailing
      # `rescue nil` here, a timeout on a facility's own detail page (which
      # we already know exists, since parse_locations found it) is treated
      # as a real, loggable error, caught by the
      # `rescue Playwright::TimeoutError` clause further down.

      unit_els = page.query_selector(".ant-list-items")&.query_selector_all("li") || []
      # Finds every unit `<li>` inside the confirmed unit-list container.
      # `&.` guards against `query_selector` itself returning nil (it
      # shouldn't, we just waited for this exact selector, but the timeout
      # above is a `wait_for_selector`, not a guarantee `query_selector`
      # succeeds a moment later), `|| []` gives an empty Array either way
      # instead of risking a `nil.query_selector_all` crash.

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Container '.ant-list-items' " \
          "was found, but had no <li> children. Site markup may have " \
          "changed, see this file's header comment for how these " \
          "selectors were confirmed. Facility URL: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
        # Exits early with an empty array, nothing more to parse for this
        # facility.
      end
      # `end` closes the `if unit_els.empty?` block.

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, "strong")
          # Confirmed live: each unit card renders its size (e.g. "5 x 5")
          # in TWO `<strong>` tags, a mobile-only one and a desktop-only
          # one (Tailwind's responsive hide/show classes, not two different
          # units), both hold identical text, so grabbing the first
          # `<strong>` (what `safe_text` does) is correct either way.
          size = parse_size(raw_size)
          # Inherited helper: extracts the two numbers out of that raw text
          # and normalizes them to a "5x5"-style string, or `nil` if it
          # couldn't find two numbers.
          next if size.blank?
          # Skip this unit if we couldn't determine a usable size.

          # Confirmed live pricing pattern: a green `<strong>` holds the
          # online rate, a line-through `<strong>` holds the regular/
          # in-store rate. This matches BaseParser's convention elsewhere
          # in this codebase (see Companies::ExtraSpace): `monthly_price`
          # is the regular/street rate, `web_special_price` is the cheaper
          # online-only rate.
          street_rate_text = safe_text(el, "strong.line-through")
          monthly_price    = parse_price(street_rate_text)

          web_rate_text     = safe_text(el, "strong.text-green-600")
          web_special_price = parse_price(web_rate_text)

          # If there's no line-through "regular" price at all, this unit
          # has one single price, not an online-vs-in-store split (matches
          # what was confirmed on non-promotional units). Fall back to the
          # green rate as the plain monthly price in that case.
          monthly_price ||= web_special_price

          # Confirmed live: a promo badge (e.g. "FIRST MONTH FREE") is a
          # plain, class-less `<span>` when a promotion applies to this
          # unit, absent otherwise.
          web_special_note = el.query_selector_all("span").map(&:text_content).map(&:strip)
                                .find { |t| t.match?(/FIRST MONTH FREE|Promotion Applied/i) }

          # Confirmed live: feature badges (e.g. "Climate Controlled",
          # "Elevator Access", "Locker") are `<span>` text next to a small
          # icon, several per unit. Collect all of them for keyword
          # matching, same best-effort approach TEMPLATE.rb suggests for a
          # site with no structured feature flags/attributes.
          feature_spans = el.query_selector_all(".flex.items-center.gap-1 span")
          features = feature_spans.map(&:text_content).map(&:strip).join(" ").downcase

          climate_controlled = features.include?("climate")
          drive_up           = features.include?("drive-up") || features.include?("outdoor")
          indoor              = !drive_up
          unit_type           = features.include?("parking") ? "parking" : "standard"

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  web_special_price == monthly_price ? nil : web_special_price,
            # If there was no real discount (single-price unit, both
            # variables came from the same green `<strong>`), don't report
            # a "special" price identical to the regular one.
            web_special_note:   web_special_note,
            admin_fee:          nil,
            insurance_note:     nil,
            climate_controlled: climate_controlled,
            available:          true,
            # No per-unit "sold out" markup was confirmed (every unit
            # checked live had an active "Select" button), every parsed
            # unit is assumed available, same fallback other real parsers
            # in this app use when a site doesn't expose that.
            drive_up:           drive_up,
            indoor:             indoor,
            unit_type:          unit_type,
            booking_url:        facility.facility_url
            # No per-unit reservation link was confirmed, every unit just
            # points back at the general facility detail page.
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

  # This site's search is path-based on full state/city names (see header
  # comment), not coordinates, reverse-geocode what we were given back into
  # a `[city, state]` pair. `state` comes back as Nominatim's full state
  # name (e.g. "Florida"), matching the confirmed "/find-storage/florida"
  # style directory (full names, not "FL").
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    # `Geocoder` is a third-party Ruby gem providing geocoding (address <->
    # coordinates lookups). `.search([lat, lng])` performs a "reverse
    # geocode", coordinates in, real-world address out, returning an Array
    # of matches; `.first` takes the best one, which may be `nil` if the
    # service found nothing at all.
    if result&.city.present?
      # `&.` safely reads `.city` off `result` only if `result` isn't
      # `nil`; `.present?` is then true if that city string is real/non-
      # blank.
      [ result.city, result.state ]
      # Builds and returns a 2-element Array, this is the last expression
      # of this `if` branch, and (since the whole if/else is the method's
      # last expression) becomes the method's return value on success.
    else
      [ lat.to_s, lng.to_s ]
      # Fallback if geocoding failed entirely: returns the raw coordinates,
      # each explicitly converted to a String via `.to_s`, so the Array
      # always holds two Strings, matching the shape callers expect either
      # way. This almost certainly won't match a real city/state on the
      # site, but guarantees the crawl fails gracefully (an unresolvable
      # search URL, zero locations found) instead of raising.
    end
    # `end` closes the `if result&.city.present? ... else ... end` branch.
  rescue => e
    # A method-level rescue (attached directly to `def`, no separate
    # `begin` needed), catches any error from the geocoding call (e.g. a
    # network failure) so a geocoding hiccup can't crash the whole crawl.
    log_warning("Reverse geocoding failed for #{lat},#{lng}: #{e.message}")
    [ lat.to_s, lng.to_s ]
    # Same raw-coordinates fallback as the `else` branch above.
  end
  # `end` closes `def reverse_geocode_city_state`.

  # Turns a "City" or "State" string (e.g. "Fort Lauderdale") into the
  # lowercase, dash-separated path segment the confirmed
  # /find-storage/<state>/<city> URLs use (e.g. "fort-lauderdale").
  def slugify(text)
    text.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    # `.to_s` guards against `nil`. `.strip.downcase` trims whitespace and
    # lower-cases everything. `.gsub(/[^a-z0-9]+/, "-")` replaces every run
    # of one-or-more characters that ISN'T a lowercase letter or digit
    # (spaces, apostrophes, periods, etc.) with a single dash, e.g. "Fort
    # Lauderdale" -> "fort-lauderdale", "St. Petersburg" -> "st-petersburg".
    # The second `.gsub(/\A-+|-+\z/, "")` strips any leading (`\A-+`) or
    # trailing (`-+\z`) dash left over from a name that started or ended
    # with a non-alphanumeric character, so we never end up with something
    # like "-miami-" or "-" for an unparseable input.
  end
  # `end` closes `def slugify`.
end
# `end` closes `class Companies::StorAmerica`.
