# =============================================================================
# COMPANY PARSER TEMPLATE
# =============================================================================
# Copy this file, rename it to your company's snake_case name (e.g. my_storage.rb)
# then implement the 4 required methods below.
#
# After creating the file, register your company in:
#   app/services/company_registry.rb
#
# Then run the recon tool to get current selectors:
#   rails runner "ReconService.run('https://www.yourcompany.com/locations/?city=gilbert&state=az')"
# =============================================================================

# NOVICE PRIMER: this file is a STARTING POINT — not a real, working parser.
# It's meant to be copied and then edited (replacing the placeholder CSS
# selectors like ".unit-list" with the real ones from the target site) to
# create a new company parser. "CSS selector" strings (e.g. ".result-list",
# "a[href^='tel:']") are the same mini-language stylesheets use to target
# HTML elements — see app/services/companies/base_parser.rb's opening
# comment block for a fuller explanation, since base_parser.rb is the parent
# class this template (and every real company file) inherits from.
# "Playwright" is the browser-automation library driving a real, invisible
# browser; `page` objects below represent one open browser tab, and
# `page.query_selector`/`page.query_selector_all` search that tab's current
# HTML for elements matching a CSS selector (returning the first match, or
# all matches, respectively).

# `class Companies::YourCompanyName < Companies::BaseParser` means: define a
# new class named `Companies::YourCompanyName` that INHERITS from
# `Companies::BaseParser` (defined in base_parser.rb). Inheritance means this
# class automatically gets every method BaseParser defines (like `run`,
# `safe_text`, `parse_price`, etc.) for free, and only needs to define the
# methods that are unique to this one company — the 4 methods stubbed out
# below.
class Companies::YourCompanyName < Companies::BaseParser
  # A Ruby "constant" (ALL_CAPS names are constants by convention) holding
  # this company's website root, so URLs built elsewhere in the file can
  # reuse it instead of repeating the domain everywhere.
  BASE_URL = "https://www.yourcompany.com"

  # The display name shown in the UI and exports
  # Example: "CubeSmart Self Storage"
  def company_name
    # `def method_name ... end` defines a method with no arguments (no
    # parentheses needed). The method's return value is whatever its last
    # (here, only) line evaluates to — a plain string literal.
    "Your Company Name"
  end
  # `end` closes `def company_name`.

  # Short identifier for logs and file names — no spaces, snake_case
  # Example: "cubesmart"
  def company_slug
    "your_company_name"
  end
  # `end` closes `def company_slug`.

  # The URL that shows storage locations near the given coordinates
  # lat and lng are GPS coordinates (e.g. 33.3528, -111.7890)
  # radius_miles is how far out to search
  #
  # Tips:
  #   - Use the recon tool to find the right URL format
  #   - Some companies use lat/lng, some use a zip code
  #   - Some companies need a two-step search (enter city, then wait for results)
  def search_url(lat, lng, radius_miles)
    # This method takes 3 ordinary ("positional") arguments — unlike
    # BaseParser's keyword-argument methods, callers pass these in order:
    # `search_url(33.35, -111.78, 10)`.
    # Replace this with the actual search URL pattern for this company
    # Example: "#{BASE_URL}/locations/?lat=#{lat}&lng=#{lng}&radius=#{radius_miles}"
    raise NotImplementedError, "Implement search_url for #{company_name}"
    # `raise ExceptionClass, "message"` immediately stops execution and
    # throws an error — this line exists so that if someone copies this
    # template and forgets to fill in a real URL, the parser fails loudly
    # (with a clear message naming the company) instead of silently
    # returning a broken/placeholder URL. `#{company_name}` interpolates the
    # result of calling the `company_name` method defined above into the
    # error message.
  end
  # `end` closes `def search_url`.

  # Parse the list of storage locations from the search results page
  # `page` is a Playwright page object — you can call page.query_selector, etc.
  #
  # Must return an Array of hashes with these keys:
  #   name:        String  — facility display name (required)
  #   address:     String  — street address (required)
  #   city:        String  — city name (required)
  #   state:       String  — 2-letter state code (required)
  #   zip:         String  — ZIP code (required)
  #   phone:       String  — phone number (optional)
  #   url:         String  — URL to the facility's pricing page (required)
  #   external_id: String  — company's own ID for this location (optional, prevents duplicates)
  def parse_locations(page)
    locations = []
    # Starts an empty Array that we'll fill with one Hash per facility found
    # on the page.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block (like
      # try/catch elsewhere): if anything inside raises an error, control
      # jumps to the matching `rescue` clause below instead of crashing the
      # whole crawl.
      # STEP 1: Wait for results to appear
      # Replace ".result-list" with the actual selector from the recon report
      page.wait_for_selector(".result-list", timeout: 15_000)
      # Tells Playwright to pause here until an element matching
      # ".result-list" appears on the page (up to 15,000ms = 15 seconds) —
      # necessary because many sites load their results via JavaScript after
      # the initial page load, so the HTML isn't there yet if we look too
      # soon. Raises `Playwright::TimeoutError` if it never shows up within
      # the timeout.

      # STEP 2: Find all location cards
      cards = page.query_selector_all(".location-card")
      # Finds every element matching ".location-card" (one per facility, in
      # this placeholder example) and returns them as an Array (empty array,
      # not an error, if none match).

      if cards.empty?
        # `.empty?` is true when the array has zero elements.
        log_warning("No location cards found. Check selectors with ReconService.")
        # `log_warning` is inherited from BaseParser — logs a warning-level
        # message tagged with this company's name.
        take_error_screenshot(page, "no_cards")
        # Also inherited from BaseParser — saves a screenshot of the current
        # page state to help debug why no cards were found.
        return []
        # `return` immediately exits `parse_locations` with an empty array —
        # nothing more to do if there are no cards.
      end
      # `end` closes the `if cards.empty?` block.

      # STEP 3: Extract data from each card
      cards.each_with_index do |card, idx|
        # `.each_with_index do |element, index| ... end` loops over every
        # item in `cards`, running the block once per card, giving the block
        # the card itself as `card` and its position (starting at 0) as
        # `idx`.
        begin
          # A second, INNER begin/rescue — so an error parsing ONE card
          # doesn't stop the loop from processing the rest of the cards.
          name    = safe_text(card, ".facility-name")   # Replace with real selector
          # `safe_text` (inherited from BaseParser) finds the first element
          # inside `card` matching the given selector and returns its
          # trimmed text, or `nil` if it's missing/empty — safer than
          # calling Playwright's raw text-reading method directly, which
          # would crash on a missing element.
          address = safe_text(card, ".street-address")  # Replace with real selector
          city    = safe_text(card, ".city")            # Replace with real selector
          state   = safe_text(card, ".state")            # Replace with real selector
          zip     = safe_text(card, ".zip")              # Replace with real selector
          phone   = safe_text(card, ".phone")           # Replace with real selector (can be nil)
          url     = safe_attr(card, "a", "href")        # Replace with real selector
          # `safe_attr` (also inherited) reads an HTML attribute (here,
          # "href" off the first `<a>` link inside `card`) safely, returning
          # nil if not found.
          url     = "#{BASE_URL}#{url}" if url&.start_with?("/")
          # `&.` is the "safe navigation operator" — calls `.start_with?`
          # only if `url` isn't nil (avoids crashing on a missing URL). If
          # the href was a site-relative path like "/store/123" (starting
          # with "/"), prefix it with `BASE_URL` to make it a full absolute
          # URL; if it was already absolute (or nil), leave it as-is.

          next if name.blank? || address.blank?
          # `next` skips the rest of THIS block iteration and moves on to
          # the next card — like `continue` in other languages. `.blank?`
          # (a Rails helper) is true for nil, empty string, or
          # whitespace-only string. Without a real name AND address, this
          # "location" isn't usable, so skip it.

          locations << {
            # `<<` is Ruby's "append" operator for arrays — pushes the Hash
            # literal that follows onto the end of the `locations` array.
            name:        name,
            address:     address,
            city:        city || "",
            # `||` = "or": if `city` is nil/false, use `""` (empty string)
            # instead, since the `city:` field is documented as required.
            state:       state || "AZ",
            # Defaults to "AZ" (Arizona) if state parsing failed — a
            # placeholder assumption specific to this template/app's market.
            zip:         zip || "",
            phone:       phone,
            url:         url,
            external_id: nil  # Add if the company exposes an ID
          }
          # `end` (implicit) — this is a Hash literal `{ ... }`, closed by
          # the `}` above; no separate `end` needed for hash literals.

        rescue => e
          # A bare `rescue => e` (no exception class named) catches any
          # `StandardError` (i.e. "normal" runtime error) and captures it
          # into local variable `e`.
          log_warning("Error parsing card ##{idx + 1}: #{e.message}")
          # `idx + 1` converts the 0-based index into a human-friendly
          # 1-based count for the log message. `e.message` is the error's
          # description text.
        end
        # `end` closes the inner `begin ... rescue ... end` wrapping one
        # card's parsing.
      end
      # `end` closes the `cards.each_with_index do |card, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      # Handles the specific case where `wait_for_selector` above timed out
      # (results never appeared within 15 seconds).
      log_error("Timeout waiting for location list: #{e.message}")
      take_error_screenshot(page, "timeout")
    rescue => e
      # Catch-all for any other unexpected error in this whole method.
      log_error("Error in parse_locations: #{e.class}: #{e.message}")
      # `e.class` is the Ruby class name of the exception (e.g.
      # "NoMethodError"), useful for diagnosing what kind of failure
      # occurred.
      take_error_screenshot(page, "error")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    locations
    # The array we built (possibly empty, possibly partially filled if some
    # cards errored) — this is the last expression evaluated in the method,
    # so it's `parse_locations`'s return value.
  end
  # `end` closes `def parse_locations`.

  # Parse unit sizes and prices from a facility's pricing page
  # `page` is a Playwright page object
  # `facility` is the Facility ActiveRecord object for this location
  #
  # Must return an Array of hashes with these keys:
  #   size:               String   — e.g. "10x20" (required)
  #   monthly_price:      Float    — regular monthly rate in dollars (optional)
  #   web_special_price:  Float    — promotional/online price (optional)
  #   web_special_note:   String   — description of the special (optional)
  #   admin_fee:          Float    — one-time admin fee in dollars (optional)
  #   insurance_note:     String   — insurance requirement note (optional)
  #   climate_controlled: Boolean  — true if climate controlled (required)
  #   available:          Boolean  — true if unit is available (required)
  #   drive_up:           Boolean  — true if outdoor/drive-up access (required)
  #   indoor:             Boolean  — true if indoor unit (required)
  #   unit_type:          String   — "standard", "locker", "parking", etc. (required)
  #   booking_url:        String   — URL to reserve this unit (optional)
  def parse_units(page, facility)
    # `facility` is an ActiveRecord object (a database row wrapper) for the
    # Facility this pricing page belongs to — used here just to read
    # `facility.name` and `facility.facility_url` for log messages.
    units = []
    # Empty Array to accumulate one Hash per unit found.

    begin
      # STEP 1: Wait for unit grid to render
      page.wait_for_selector(".unit-list", timeout: 15_000)  # Replace with real selector
      # Same pattern as parse_locations above: wait up to 15 seconds for the
      # unit listing container to actually appear in the page.

      # STEP 2: Find all unit elements
      unit_els = page.query_selector_all(".unit-item")  # Replace with real selector
      # Finds every element representing one storage unit listing.

      if unit_els.empty?
        log_warning("No units found at #{facility.name}. Run ReconService on: #{facility.facility_url}")
        # `facility.name`/`facility.facility_url` read columns off the
        # ActiveRecord `facility` object, same as reading attributes on any
        # Ruby object.
        return []
      end
      # `end` closes the `if unit_els.empty?` block.

      # STEP 3: Extract data from each unit
      unit_els.each_with_index do |el, idx|
        begin
          raw_size = safe_text(el, ".unit-size")    # Replace with real selector
          size     = parse_size(raw_size)
          # `parse_size` (inherited from BaseParser) normalizes a size
          # string like "10' x 20'" into "10x20", or returns nil if it can't
          # find two numbers in the text.
          next if size.blank?
          # Skip this unit entirely if we couldn't determine a valid size.

          price_text    = safe_text(el, ".price")   # Replace with real selector
          monthly_price = parse_price(price_text)
          # `parse_price` (inherited) strips out currency symbols/text and
          # converts what's left to a rounded Float, or nil if unparseable.

          # Detect climate control from text or data attributes
          features      = safe_text(el, ".features") || ""
          # Falls back to an empty string if `.features` wasn't found, so
          # the `.downcase.include?` calls below don't crash on nil.
          cc            = features.downcase.include?("climate")
          # `.downcase` lowercases the text so the check is
          # case-insensitive; `.include?("climate")` is true if that
          # substring appears anywhere in the features text.

          # Detect drive-up
          drive_up      = features.downcase.include?("drive-up") ||
                          features.downcase.include?("outdoor")
          # `||` = "or" — true if EITHER phrase appears in the features
          # text. This condition spans two lines; Ruby allows an expression
          # to continue onto the next line when it ends with an operator
          # like `||` that clearly isn't a complete statement yet.

          units << {
            size:               size,
            monthly_price:      monthly_price,
            web_special_price:  nil,     # Add if the company shows a web price
            web_special_note:   nil,
            admin_fee:          nil,
            insurance_note:     nil,
            climate_controlled: cc,
            available:          true,    # Update if the site shows availability
            drive_up:           drive_up,
            indoor:             !drive_up,
            # `!` is Ruby's "not" operator — `indoor` is simply the opposite
            # of `drive_up` in this placeholder logic (a unit is assumed
            # indoor unless it was detected as drive-up/outdoor).
            unit_type:          "standard",  # Update if you detect type from page
            booking_url:        facility.facility_url
            # Falls back to the general facility page URL since this
            # template doesn't have a per-unit booking link selector filled
            # in yet.
          }

        rescue => e
          log_warning("Error parsing unit ##{idx + 1} at #{facility.name}: #{e.message}")
        end
        # `end` closes the inner `begin ... rescue ... end` for one unit.
      end
      # `end` closes the `unit_els.each_with_index do |el, idx| ... end` loop.

    rescue Playwright::TimeoutError => e
      log_error("Timeout loading units at #{facility.name}: #{e.message}")
      take_error_screenshot(page, "timeout_#{facility.id}")
      # `facility.id` reads the database primary-key ID of this facility, so
      # the screenshot filename is unique per facility even across repeated
      # crawl runs.
    rescue => e
      log_error("Error in parse_units for #{facility.name}: #{e.class}: #{e.message}")
    end
    # `end` closes the outer `begin ... rescue ... rescue ... end` block.

    units
    # Return value: the array of unit hashes built above.
  end
  # `end` closes `def parse_units`.
end
# `end` closes `class Companies::YourCompanyName`.
