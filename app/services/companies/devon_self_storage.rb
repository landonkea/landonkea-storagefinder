# =============================================================================
# DEVON SELF STORAGE PARSER
# =============================================================================
# Crawls devonselfstorage.com to find facilities and unit pricing.
#
# Website behavior notes (verified by driving the live site — see recon/ for
# saved HTML/screenshots, and ad-hoc scratch scripts used during development):
#   - /locations/ (the stub's guess) 404s. The real search box lives on the
#     homepage (#markets-autocomplete-input, form action="/search") and takes
#     free-text "City, State". Selecting an autocomplete suggestion renders
#     results as an in-page overlay WITHOUT changing window.location (a
#     Next.js intercepted route) — but critically, navigating directly to
#     "/search?q=<City>%2C+<ST>" (no interactive typing needed) renders the
#     exact same results server-side. We reverse-geocode the lat/lng we're
#     given into "City, ST" (Geocoder gem) and build that URL ourselves, same
#     pattern as Companies::PublicStorage / Companies::UHaul.
#   - The search results page has no radius query param — it just lists the
#     nearest facilities to the searched city. We don't attempt to enforce
#     radius_miles client-side; the same limitation applies to the working
#     Public Storage / U-Haul parsers.
#   - Facility cards render server-side as `article.facility-card` (inside
#     `section.facility-grid`). Each card carries rich data attributes
#     (data-title, data-lat, data-lng, data-features) and TWO duplicate
#     `address.address` blocks (one for the map info-window, one for the
#     list row) — must scope to the FIRST `address.address` per card, not
#     `query_selector_all("address.address span")` on the whole card, or the
#     street/city-state-zip lines from both blocks interleave.
#   - Each facility's own detail page (linked via `a[href^="/storage-locations/"]`,
#     both the "Visit Location" and "Available Units" buttons point to the
#     same URL) renders unit pricing server-side as `div.unit-item` blocks —
#     dimension, category, feature list, promo text, and price are all
#     present without any extra API call.
#   - Per-unit price is a single "Starting at $X.XX" value (`.unit-item-price__web-rate`)
#     — there's no separate strikethrough/list price in the markup, so we
#     treat any promo text (e.g. "First Month FREE", "Half Month FREE") as
#     web_special_note rather than a numeric web_special_price.
#   - `data-features` on each unit-item is a comma-separated list, e.g.
#     "climate-control,ground-level,inside" or "outside-drive-up-unit" or
#     "outside-drive-up-unit,covered-parking". climate_controlled/drive_up/
#     indoor are all derived from this list.
#   - Parking spaces (`data-categories="parking"`) only have a single
#     dimension (e.g. "26'"), so parse_size (which requires two numbers)
#     naturally drops them — consistent with how they'd be filtered out
#     downstream anyway (apply_filters excludes drive_up/non-indoor units).
#   - No bot-detection / CAPTCHA / "press and hold" challenge was encountered
#     at any point (homepage, direct /search?q= navigation, or facility
#     detail pages) — real facility and unit data rendered directly in the
#     HTML every time.
#
# If the site layout changes, run the recon tool:
#   rails runner "ReconService.run('https://www.devonselfstorage.com/search?q=Gilbert%2C+AZ')"
# =============================================================================

# NOVICE PRIMER: `class Companies::DevonSelfStorage < Companies::BaseParser`
# defines this class as a SUBCLASS ("child class") of `Companies::BaseParser`
# (see app/services/companies/base_parser.rb) — it INHERITS every method
# BaseParser defines (like `run`, `safe_text`, `safe_attr`, `safe_all_text`,
# `parse_price`, `parse_size`, `log_info`, `log_warning`, `log_error`,
# `take_error_screenshot`) and only has to implement the 4 methods that are
# unique to Devon's own website (company_name, company_slug, search_url,
# parse_locations, parse_units). "Playwright" is the browser-automation
# library this whole file drives: a `page` object represents one open,
# invisible ("headless") browser tab, and the CSS-selector strings you'll see
# below (like "article.facility-card") are the same mini-language stylesheets
# use to target HTML elements — a leading `.` means "match this CSS class", no
# leading symbol means "match this HTML tag name", and `[attr^='x']` means
# "match an attribute whose value STARTS WITH x". See base_parser.rb's opening
# comment for a fuller explanation of selectors and of Ruby's
# `protected`/`private` method-visibility keywords, both of which apply here
# too.
class Companies::DevonSelfStorage < Companies::BaseParser
  # A Ruby "constant" (any ALL_CAPS name) holding Devon's website root,
  # reused below whenever a relative "/foo" link found on the page needs to
  # become a full, clickable URL.
  BASE_URL = "https://www.devonselfstorage.com"

  # Overrides BaseParser's abstract `company_name` — the required display
  # name shown in the UI/exports for this company. `def ... end` with no
  # parentheses is a method that takes no arguments; its return value is
  # whatever its last (and here, only) line evaluates to — a bare string.
  def company_name
    "Devon Self Storage"
  end
  # `end` closes `def company_name`.

  # Overrides BaseParser's abstract `company_slug` — a short, file-name- and
  # log-line-safe identifier for this company.
  def company_slug
    "devon_self_storage"
  end
  # `end` closes `def company_slug`.

  # Overrides BaseParser's abstract `search_url` — builds the URL for
  # Devon's search-results page given GPS coordinates and a radius (the
  # radius argument is accepted for interface compatibility with
  # BaseParser#run but isn't actually usable — see the header notes above).
  def search_url(lat, lng, radius_miles)
    location_query = reverse_geocode_city_state(lat, lng)
    # Calls the private helper defined near the bottom of this file, which
    # turns raw GPS coordinates into a "City, ST" string — Devon's search box
    # takes free text, not coordinates.

    "#{BASE_URL}/search?q=#{ERB::Util.url_encode(location_query)}"
    # String interpolation (`#{...}`) builds the search URL.
    # `ERB::Util.url_encode` is a Rails/Ruby helper that "percent-encodes" a
    # string for safe use inside a URL — e.g. it turns the space and comma in
    # "Gilbert, AZ" into "%2C" and "+"/"%20", so the browser/server correctly
    # parses it as one query value instead of getting confused by special
    # characters. This is the last (and only) expression in the method, so
    # it's the method's return value.
  end
  # `end` closes `def search_url`.

  # Overrides BaseParser's abstract `parse_locations` — reads the list of
  # nearby Devon facilities off the search-results page.
  def parse_locations(page)
    locations = []
    # An empty Array that will collect one Hash per facility found on the
    # page.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block (like
      # try/catch elsewhere) — code inside `begin` runs normally; if it
      # raises an error, control jumps to the matching `rescue` clause below
      # instead of crashing this method entirely.
      page.wait_for_selector("article.facility-card", timeout: 15_000) rescue nil
      # Waits up to 15,000ms (15 seconds) for at least one facility card to
      # appear in the page's HTML. The trailing `rescue nil` is Ruby's
      # one-line rescue modifier: if `wait_for_selector` raises ANY error
      # (most likely a timeout, because this search location has zero
      # results), that error is swallowed and the whole expression becomes
      # `nil` instead of crashing — execution just falls through to the next
      # line, where `query_selector_all` below will simply find zero cards
      # and the "empty" branch further down handles that cleanly.

      cards = page.query_selector_all("article.facility-card")
      # Finds every facility-card element on the page. Returns an empty
      # Array (never nil) if none match.

      if cards.empty?
        # `.empty?` is true when the Array has zero elements.
        log_warning(
          "No facility cards found on Devon Self Storage search page " \
          "(selector: 'article.facility-card'). This may mean the searched " \
          "city/state genuinely has no nearby Devon locations, or the page " \
          "layout changed — run ReconService to check."
        )
        # The trailing `\` at the end of each string line lets a Ruby string
        # literal continue onto the next source line without inserting an
        # actual newline character — purely to keep the source lines from
        # getting too long; the three pieces get concatenated into one
        # message.
        take_error_screenshot(page, "no_cards")
        # Inherited helper (from BaseParser) that saves a PNG screenshot of
        # the current page to the logs/ folder, tagged with this label, so a
        # developer can see what actually rendered.
        return []
        # `return` immediately exits `parse_locations` here with an empty
        # array — there's nothing left to parse.
      end
      # `end` closes the `if cards.empty?` block.

      log_info("Found #{cards.length} Devon Self Storage locations")
      # `.length` on an Array returns how many elements it has.

      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` walks through every
        # element of `cards`, running the block once per card, handing it to
        # the block as `card` and its position (starting at 0) as `idx`.
        begin
          # Inner begin/rescue: an error parsing ONE card shouldn't stop the
          # rest of the cards from being processed.
          name = card.get_attribute("data-title")&.strip
          # `.get_attribute("data-title")` reads the custom `data-title`
          # HTML attribute off this card element (or `nil` if it isn't
          # present). `&.` is Ruby's "safe navigation operator" — it calls
          # `.strip` only if the value on its left isn't `nil`, avoiding a
          # crash if the attribute was missing.

          link    = card.query_selector("a[href^='/storage-locations/']")
          # `a[href^='/storage-locations/']` is an "attribute selector"
          # combined with a tag name: it matches an `<a>` element whose
          # `href` attribute STARTS WITH "/storage-locations/" (`^=` means
          # "starts with"). Finds this facility's detail-page link.
          rel_url = link&.get_attribute("href")
          # Reads the relative URL (e.g. "/storage-locations/gilbert-az") off
          # that link, safely handling `link` being `nil` if no such link was
          # found on this card.
          url     = rel_url ? "#{BASE_URL}#{rel_url}" : nil
          # Ruby's ternary operator: `condition ? value_if_true :
          # value_if_false`. If `rel_url` is present (truthy), prefix it with
          # `BASE_URL` to build a full absolute URL; otherwise `url` is
          # `nil`.

          # Each card has TWO duplicate address.address blocks (map
          # info-window + list row) — scope to the first one only, or the
          # street/city-state-zip lines from both blocks interleave.
          first_address = card.query_selector("address.address")
          # Finds the FIRST `<address class="address">` element inside this
          # card (`query_selector`, unlike `query_selector_all`, always
          # returns just one match or `nil`) — deliberately ignoring any
          # second, duplicate address block elsewhere in the card.
          address_lines = first_address ? safe_all_text(first_address, "span") : []
          # `safe_all_text` (inherited from BaseParser) returns the trimmed
          # text of every `<span>` inside `first_address`, as an Array of
          # Strings — but only if `first_address` was actually found;
          # otherwise this falls back to an empty Array so the code below
          # doesn't crash indexing into it.

          street              = address_lines[0]
          # Array indexing: the first captured text line, expected to be the
          # street address.
          city_part, state_zip = address_lines[1].to_s.split(",", 2)
          # "Multiple assignment": Ruby unpacks the two-element Array
          # returned by `.split` into two separate local variables in one
          # line. `.to_s` guards against `address_lines[1]` being `nil` (if
          # there was no second line) by converting it to an empty string
          # first, so `.split` never crashes. `.split(",", 2)` splits on the
          # first comma only (the `2` limits it to at most 2 pieces), e.g.
          # "Gilbert, AZ 85296" -> ["Gilbert", " AZ 85296"].
          city                = city_part&.strip
          # Trims whitespace off the city piece, safely handling `city_part`
          # being `nil` (e.g. if there was no comma at all to split on).
          state_zip_parts     = state_zip.to_s.strip.split(/\s+/)
          # `.to_s` guards against `state_zip` being `nil` again, `.strip`
          # trims leading/trailing whitespace, then `.split(/\s+/)` splits on
          # one-or-more whitespace characters (`\s+` is a regular expression
          # meaning "one or more spaces/tabs") — turning " AZ 85296" into
          # ["AZ", "85296"].
          state               = state_zip_parts[0]
          zip                 = state_zip_parts[1]

          phone = safe_text(card, ".phone")
          # Inherited helper: finds the first element matching ".phone"
          # inside `card` and returns its trimmed text, or `nil` if not
          # found.

          external_id = card.get_attribute("id").to_s[/facility-card-(\d+)/, 1]
          # Reads this card's own `id` HTML attribute (e.g.
          # "facility-card-482"), `.to_s` guards against `nil`, and then
          # `[...]` with a regex argument is Ruby's "String#[]" pattern-match
          # form: it looks for the regex `/facility-card-(\d+)/` inside the
          # string (`\d+` = one or more digits, wrapped in parentheses to
          # form a "capture group") and, because a second argument `1` is
          # given, returns just the text captured by that first group (the
          # digits) — or `nil` if the pattern didn't match at all.

          next if street.blank?
          # `.blank?` (a Rails helper) is true for `nil`, an empty string, or
          # a whitespace-only string. `next` skips the rest of THIS block
          # iteration (this one card) and moves on to the next card in the
          # loop — reached when we couldn't even find a usable street
          # address, so this card isn't worth keeping.

          locations << {
            # `<<` is Ruby's "append" operator for arrays — pushes a new
            # element (here, a Hash literal describing one location) onto
            # the end of the `locations` array.
            name:        name.presence || "Devon Self Storage - #{street}",
            # `.presence` (Rails helper) returns `name` itself if it's
            # non-blank, or `nil` if it's blank — `||` ("or") then falls back
            # to a generated name like "Devon Self Storage - 123 Main St" if
            # no real name was scraped.
            address:     street,
            city:        city || "",
            # `||` falls back to an empty string if `city` came back `nil`,
            # so downstream code always gets a String, never `nil`.
            state:       state || "AZ",
            # Same fallback pattern, but defaults to the literal string
            # "AZ" instead of "" — see the "flag but don't fix" note at the
            # end of this review: this assumes searches are AZ-based, which
            # may not always be true.
            zip:         zip || "",
            phone:       phone,
            url:         url,
            external_id: external_id
          }

          log_info("  ✓ #{street} — #{city}, #{state}")
          # A checkmark-prefixed info log line for each successfully parsed
          # location, useful for eyeballing crawl progress while watching
          # logs live.

        rescue => e
          # A bare `rescue => e` (no exception class listed) catches
          # `StandardError` and its subclasses — i.e. "any ordinary error" —
          # and captures the exception object into a local variable `e`.
          log_warning("Error parsing Devon Self Storage card ##{idx + 1}: #{e.class}: #{e.message}")
          # `e.class` is the exception's Ruby class name (e.g.
          # "NoMethodError"); `e.message` is its human-readable description.
          # `idx + 1` converts the 0-based loop index into a friendlier
          # 1-based count for the log message.
        end
        # `end` closes the inner `begin ... rescue ... end` wrapping the
        # parsing of one card.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop
      # — every card has now been processed.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue only catches errors of the specific type
      # `Playwright::TimeoutError` that happen anywhere else in the
      # surrounding `begin` block (not already swallowed by the `rescue nil`
      # above) — for example if `query_selector_all` itself somehow times
      # out.
      log_error("Timeout waiting for Devon Self Storage search results. Error: #{e.message}")
      take_error_screenshot(page, "search_timeout")
    rescue => e
      # A bare `rescue => e` here comes AFTER the more specific
      # `Playwright::TimeoutError` rescue — Ruby checks `rescue` clauses
      # top-to-bottom and uses the first one that matches the error's type,
      # so this one is the catch-all for anything else unexpected.
      log_error("Unexpected error parsing Devon Self Storage locations: #{e.class}: #{e.message}")
      take_error_screenshot(page, "parse_locations_error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # The last expression evaluated in the method — the `locations` Array
    # built above — becomes `parse_locations`'s return value.
  end
  # `end` closes `def parse_locations`.

  # Overrides BaseParser's abstract `parse_units` — reads unit sizes/prices
  # off one facility's own detail page.
  def parse_units(page, facility)
    units = []
    # Empty Array to collect one Hash per unit found.

    begin
      page.wait_for_selector("div.unit-item", timeout: 15_000)
      # Waits up to 15 seconds for at least one unit block to render. Unlike
      # `parse_locations` above, there's no trailing `rescue nil` here — a
      # timeout on a facility's OWN detail page (which we already know
      # exists, since parse_locations found it) is treated as a real,
      # loggable error, caught by the `rescue Playwright::TimeoutError`
      # clause further down.

      unit_els = page.query_selector_all("div.unit-item")
      # Finds every unit block on this facility's detail page.

      if unit_els.empty?
        log_warning(
          "No units found at #{facility.name}. Selector: 'div.unit-item'. " \
          "Run ReconService on: #{facility.facility_url}"
        )
        take_error_screenshot(page, "no_units_#{facility.id}")
        return []
        # Exits early with an empty array — nothing more to parse for this
        # facility.
      end
      # `end` closes the `if unit_els.empty?` block.

      log_info("Found #{unit_els.length} units at #{facility.name}")

      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".unit-item__dimension")
          # Reads the raw dimension text (e.g. "10' x 10'") for this unit.
          size     = parse_size(raw_size)
          # Inherited helper: extracts the two numbers out of that raw text
          # and normalizes them to a "10x10"-style string, or `nil` if it
          # couldn't find two numbers.
          next if size.blank?
          # Skip this unit if we couldn't determine a usable size.

          price_text    = safe_text(el, ".unit-item-price__web-rate")
          # Reads the "Starting at $X.XX" price text for this unit.
          monthly_price = parse_price(price_text)
          # Inherited helper: strips out everything except digits/decimal
          # point and converts to a Float, or `nil` if unparseable.
          next if monthly_price.blank?
          # Skip this unit if we ended up with no usable price.

          features = el.get_attribute("data-features").to_s.split(",").map(&:strip)
          # Reads the custom `data-features` attribute (a comma-separated
          # list like "climate-control,ground-level,inside"), `.to_s` guards
          # against `nil`, `.split(",")` breaks it into pieces on each comma,
          # and `.map(&:strip)` trims whitespace off every piece — `&:strip`
          # is shorthand for `{ |s| s.strip }`, applying the `.strip` method
          # to each element via `.map`.
          category = el.get_attribute("data-categories").to_s.strip.downcase
          # Reads the custom `data-categories` attribute (e.g. "parking" or
          # "small"), guarding against `nil`, trimming whitespace, and
          # lower-casing it for a reliable case-insensitive comparison below.

          climate_controlled = features.include?("climate-control")
          # `.include?` is true if the Array contains an element that
          # exactly equals the given string.
          drive_up           = features.any? { |f| f.include?("drive-up") }
          # `.any? { |f| ... }` is true if the block returns truthy for AT
          # LEAST ONE element of `features`. Here, String#include? checks
          # each feature string for the substring "drive-up" (so it matches
          # both "outside-drive-up-unit" and any other feature containing
          # that text).
          indoor             = features.include?("inside") && !drive_up
          # A unit only counts as indoor if the feature list explicitly says
          # "inside" AND it's not also a drive-up unit. `&&` requires both
          # sides to be true; `!` negates `drive_up`.

          # No separate strikethrough price in the markup — promo text like
          # "First Month FREE" / "Half Month FREE" is a value-add note, not
          # a numeric discount, so it becomes web_special_note only.
          web_special_note = safe_text(el, ".unit-item__promotions")
          # Reads any promotional text shown for this unit.

          unit_type = category == "parking" ? "parking" : "standard"
          # Ternary: if the `category` string equals "parking" exactly, use
          # "parking" as the unit_type; otherwise "standard".

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  nil,
            # Devon's markup never exposes a separate numeric discount price
            # (see the header comment above) — always nil for this company.
            web_special_note:   web_special_note,
            admin_fee:          nil,
            # Not exposed on Devon's unit markup — left nil.
            insurance_note:     nil,
            # Same — not exposed, left nil.
            climate_controlled: climate_controlled,
            available:          true,
            # Devon's listing doesn't expose per-unit "sold out" status in
            # what we scrape, so every parsed unit is assumed available.
            drive_up:           drive_up,
            indoor:             indoor,
            unit_type:          unit_type,
            booking_url:        facility.facility_url
            # Devon's unit markup doesn't carry a per-unit reservation link
            # (unlike some other companies' parsers) — every unit just
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
  # Ruby's `private` keyword: everything defined below this line is an
  # internal implementation detail — it can only be called from inside this
  # class's own methods (using an implicit receiver, i.e. just
  # `reverse_geocode_city_state(...)`, never
  # `some_object.reverse_geocode_city_state(...)`), never from outside code.

  # Devon's search box takes a free-text "City, State" query, not
  # coordinates — reverse-geocode what we were given back into that form.
  def reverse_geocode_city_state(lat, lng)
    result = Geocoder.search([ lat, lng ]).first
    # `Geocoder` is a third-party Ruby gem providing geocoding (address <->
    # coordinates lookups). `.search([lat, lng])` performs a "reverse
    # geocode" — given coordinates, find the real-world address — returning
    # an Array of possible matches; `.first` takes the best match, which may
    # be `nil` if the service found nothing at all.
    if result&.city.present?
      # `&.` safely reads `.city` off `result` only if `result` isn't `nil`;
      # `.present?` is then true if that city string is real/non-blank.
      "#{result.city}, #{result.state}"
      # Builds and returns a "City, State" string, e.g. "Gilbert, Arizona" —
      # this is the last expression of this `if` branch, and since the whole
      # `if/else` is the last expression in the method, it becomes this
      # method's return value on the success path.
    else
      "#{lat},#{lng}"
      # Fallback if geocoding failed entirely: returns the raw coordinates
      # as a string instead. This almost certainly won't match a real city
      # on Devon's site, but guarantees the method always returns SOME
      # string rather than crashing, so the crawl can still fail gracefully
      # (search_url will just build a URL that finds no results) instead of
      # erroring out entirely.
    end
    # `end` closes the `if result&.city.present? ... else ... end` branch.
  rescue => e
    # A method-level rescue (attached directly to `def`, no separate
    # `begin` block needed) — catches any error from the geocoding call
    # (e.g. a network failure) so a geocoding hiccup can't crash the whole
    # crawl.
    log_warning("Reverse geocoding failed for #{lat},#{lng}: #{e.message}")
    "#{lat},#{lng}"
    # Same raw-coordinates fallback as the `else` branch above.
  end
  # `end` closes `def reverse_geocode_city_state`.
end
# `end` closes `class Companies::DevonSelfStorage`.
