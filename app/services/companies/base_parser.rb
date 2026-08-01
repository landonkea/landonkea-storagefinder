# =============================================================================
# BASE PARSER
# =============================================================================
# Every company parser inherits from this class.
# It provides shared functionality so each company parser only has to implement
# the parts that are unique to that company's website.
#
# TO ADD A NEW COMPANY:
#   1. Create a new file in app/services/companies/
#   2. Name it snake_case matching the company (e.g. my_storage_co.rb)
#   3. Inherit from BaseParser
#   4. Implement the required methods listed below
#   5. Register it in CompanyRegistry (app/services/company_registry.rb)
#
# REQUIRED METHODS TO IMPLEMENT IN SUBCLASS:
#   - company_name    → String, e.g. "Extra Space Storage"
#   - company_slug    → String, e.g. "extra_space" (used in logs and file names)
#   - search_url(lat, lng, radius_miles) → String URL to search for locations
#   - parse_locations(page) → Array of { name:, address:, city:, state:, zip:, phone:, url: }
#   - parse_units(page, facility) → Array of unit attribute hashes
# =============================================================================

# NOVICE PRIMER — read this before the rest of the file:
#
# 1. "class Foo < Bar" means "define a class named Foo that INHERITS from Bar."
#    Inheritance means Foo automatically gets every method Bar defines, without
#    Foo having to rewrite them. Foo is called the "subclass" (or "child
#    class") and Bar is the "superclass" (or "parent class"). Here,
#    `Companies::BaseParser` is the parent, and every company-specific file in
#    this folder (cube_smart.rb, extra_space.rb, etc.) is a child class that
#    writes `class Companies::CubeSmart < Companies::BaseParser`. That child
#    class gets `run`, `open_page`, `safe_text`, and every other method
#    defined below for free — it only has to define the handful of methods
#    that are actually different per company (company_name, search_url, etc).
#
# 2. "Playwright" is a browser-automation library: Ruby code in this file
#    tells a real (invisible/"headless") web browser to open a page, click
#    things, and read back what's on the page — exactly like a human browsing
#    the site, except driven by code. A "page" object (you'll see `page.` all
#    over this file) represents one open browser tab.
#
# 3. A "CSS selector" (strings like ".price-label" or "a[href^='tel:']") is
#    the same mini-language used in stylesheets to target HTML elements. A
#    leading `.` means "class", e.g. ".unit-item" matches any element with
#    `class="unit-item"`. No leading symbol means a tag name, e.g. "a" matches
#    `<a>` links. `[attr='value']` matches an attribute exactly; `[attr^='x']`
#    matches an attribute that STARTS WITH "x". Playwright's
#    `page.query_selector(selector)` finds the FIRST matching element (or nil
#    if none exists); `page.query_selector_all(selector)` finds ALL matching
#    elements and returns them as an Array (empty array, not nil, if none
#    match).
#
# 4. `protected` and `private` (both appear below) are Ruby keywords that
#    restrict who can call a method. Everything defined ABOVE one of these
#    keywords in the file is a normal ("public") method, callable from
#    anywhere. Everything defined BELOW `protected` can only be called by code
#    inside this class or a subclass of it (i.e. the company parser files) —
#    outside code (like the job that kicks off a crawl) cannot call them
#    directly. `private` is even stricter: only this exact class (and,
#    practically here, subclasses calling with an implicit receiver) can call
#    it, and never with an explicit receiver like `some_object.the_method`.
#    The point is to hide "helper" methods that are implementation details,
#    so the only thing the outside world is meant to call is `run`.
class Companies::BaseParser
  # ---------------------------------------------------------------------------
  # CONFIGURATION — subclasses can override these
  # ---------------------------------------------------------------------------

  # A Ruby "constant" — by convention, any variable name written in
  # ALL_CAPS is treated as a constant (a value that isn't meant to change).
  # This one sets how many times to retry a failed page load before giving up.
  MAX_RETRIES = 3

  # How long to wait between retries (in milliseconds). "_MS" in the name is
  # just a naming convention reminding readers of the unit (milliseconds,
  # i.e. thousandths of a second) — Ruby doesn't enforce units.
  RETRY_DELAY_MS = 3000

  # How long to wait for a page to load before timing out (in milliseconds)
  PAGE_TIMEOUT_MS = 30_000
  # (The underscore in 30_000 is just a readability separator, like a comma —
  # Ruby ignores underscores inside number literals, so 30_000 == 30000.)

  # How long to wait after a page loads for JS (JavaScript) to finish
  # rendering (ms). Many storage sites fetch prices via JavaScript AFTER the
  # initial HTML arrives, so we pause here to give that time to happen.
  JS_SETTLE_DELAY_MS = 2000

  # ---------------------------------------------------------------------------
  # INITIALIZER
  # ---------------------------------------------------------------------------
  # crawl_run: the CrawlRun record this parser is working on behalf of
  # browser:   a Playwright browser instance shared across parsers
  # options:   hash of filter options from the user's crawl settings
  # ---------------------------------------------------------------------------
  # `initialize` is Ruby's special method name for "the constructor" — it runs
  # automatically whenever someone writes `Companies::CubeSmart.new(...)`.
  # The parameter list here uses "keyword arguments": `crawl_run:`, `browser:`,
  # and `options:` (with `options: {}` giving it a default empty hash `{}` if
  # the caller doesn't pass one). Keyword arguments must be passed by name at
  # the call site, e.g. `.new(crawl_run: run, browser: b)`, which makes the
  # call self-documenting compared to plain positional arguments.
  def initialize(crawl_run:, browser:, options: {})
    @crawl_run = crawl_run    # The CrawlRun record — used for logging
    # `@crawl_run` (with an `@` prefix) is an "instance variable" — it's
    # attached to this specific object and stays available in every other
    # method of this object (unlike a plain local variable, which only lives
    # inside the method it's declared in).
    @browser   = browser      # Playwright browser — used to open pages
    # Same idea: stash the shared Playwright browser instance so `open_page`
    # (further down) can use it to open new tabs.
    @options   = options      # Filter options (sizes, climate_controlled, etc.)
    # Stash the user's filter choices (e.g. which unit sizes they care about)
    # so `apply_filters` (further down) can use them later.

    # Create a logger tagged with this company's name so log lines are identifiable
    @logger = Rails.logger.tagged(company_name)
    # `Rails.logger` is Rails' built-in logging object (writes to the log
    # file/console). `.tagged(...)` wraps it so every message it logs gets
    # prefixed with the company name (e.g. "[CubeSmart] ..."), making it easy
    # to tell which company's crawl produced which log line when several
    # crawls run concurrently. `company_name` here calls the method defined
    # further down in this same class — since subclasses override it, this
    # will actually invoke the SUBCLASS's version (e.g. CubeSmart's, which
    # returns "CubeSmart") even though we're inside BaseParser's code. This
    # is called "polymorphism": the same method call resolves differently
    # depending on the actual (subclass) type of the object.
  end
  # `end` closes the `def initialize` method definition that started above.

  # ---------------------------------------------------------------------------
  # MAIN ENTRY POINT
  # ---------------------------------------------------------------------------
  # This is the method called by the CrawlJob to run this company's parser.
  # Subclasses should NOT override this — override parse_locations and parse_units instead.
  # ---------------------------------------------------------------------------
  # Again, keyword arguments: callers must invoke this as
  # `.run(search_lat: ..., search_lng: ..., radius_miles: ...)`.
  def run(search_lat:, search_lng:, radius_miles:)
    log_info("Starting crawl for #{company_name}")
    # `#{...}` inside a double-quoted string is Ruby "string interpolation" —
    # it runs the Ruby expression inside the braces and inserts its result as
    # text. So this logs something like "Starting crawl for CubeSmart".

    facilities_saved = 0
    # Local variable (no `@`) counting how many facilities we successfully
    # saved to the database during this run — starts at zero.
    units_saved      = 0
    # Same idea, counting individual storage units saved.

    begin
      # `begin ... rescue ... end` is Ruby's exception-handling block — like
      # try/catch in other languages. Code inside `begin` runs normally; if
      # it raises an error, execution jumps to the matching `rescue` clause
      # instead of crashing the whole program. This lets one company's crawl
      # fail gracefully (logging the error) instead of taking down the
      # process.
      # Step 1: Open the search page and get a list of facility locations
      log_info("Opening search URL for coordinates #{search_lat}, #{search_lng}")

      search_page_url = search_url(search_lat, search_lng, radius_miles)
      # Calls the subclass's `search_url` method (each company implements its
      # own — see e.g. cube_smart.rb) to build the URL for the search results
      # page for this company, given the coordinates and radius.
      page = open_page(search_page_url)
      # `open_page` (defined further down, in the `protected` section) opens
      # a real browser tab at that URL and returns the Playwright page object
      # representing it, with retry logic baked in.

      # Step 2: Extract location data from the search results page
      log_info("Parsing location list from search results page")
      locations = parse_locations(page)
      # Calls the SUBCLASS's `parse_locations` method (each company must
      # implement this) to read the list of storage facilities off the page
      # and return them as an Array of Hashes (see the required-keys comment
      # near the abstract method definition further down).

      if locations.empty?
        # `.empty?` is true for an Array (or String, Hash, etc.) with zero
        # elements. If the subclass's parser found no locations at all, we
        # can't do anything more for this company on this run.
        log_warning("No locations found on search page. The page layout may have changed.")
        log_warning("URL: #{search_page_url}")
        take_error_screenshot(page, "no_locations_found")
        # Saves a screenshot of the (probably broken) page so a developer can
        # see what actually rendered, to help debug why parsing found
        # nothing.
        return { facilities: 0, units: 0 }
        # `return` immediately exits the `run` method with this Hash as the
        # result — no locations means nothing more to do.
      end
      # `end` closes the `if locations.empty?` block above.

      log_info("Found #{locations.length} location(s) listed")

      # Step 3: For each location, visit its page and extract unit prices
      #
      # REFACTORING NOTE: the per-location work used to be inlined directly
      # in this loop (upsert facility, open its page, parse/filter/save
      # units, two rescue clauses — around 100 lines) — a comment/refactor
      # audit flagged it as a self-contained unit of work that could be
      # pulled out, matching this file's own established pattern of small,
      # single-purpose helpers (open_page, apply_filters, save_unit,
      # upsert_facility are all already separate methods below). It's now
      # `process_location` (in the `protected` section further down),
      # which returns a `[facility_saved, units_saved_count]` pair — this
      # loop just accumulates those pairs into the running totals.
      locations.each_with_index do |location_data, index|
        # `.each_with_index do |element, index| ... end` is a Ruby loop: it
        # walks through every element of the `locations` array, running the
        # block (the code between `do` and `end`) once per element, handing
        # that element to the block as `location_data` and its position
        # (starting at 0) as `index`.
        log_info("Processing location #{index + 1}/#{locations.length}: #{location_data[:name]}")
        # `location_data[:name]` reads the value stored under the `:name` key
        # of this location's Hash. `:name` (with a leading colon) is a Ruby
        # "symbol" — a lightweight, immutable label commonly used as a Hash
        # key, similar to a string but more memory-efficient since identical
        # symbols are the same object in memory.

        # `process_location` handles its OWN error cases internally (a
        # timed-out page load, or any other unexpected error for this ONE
        # location) and always returns a `[facility_saved, units_saved]`
        # pair — `[false, 0]` if this location failed for any reason — so
        # there's no begin/rescue needed here at all; one bad location can
        # never stop the rest of this loop from running.
        facility_saved, units_saved_here = process_location(location_data)
        facilities_saved += 1 if facility_saved
        units_saved      += units_saved_here

        # Polite delay between location requests — avoids overwhelming the site
        # and helps with rate limiting on slow hardware
        delay_ms = Setting.get("crawl_delay_between_requests_ms", default: 2000).to_i
        # Reads a configurable delay (in milliseconds) from the app's
        # `Setting` model, defaulting to 2000ms (2 seconds) if it isn't set.
        # `.to_i` converts whatever comes back into an Integer, just in case.
        sleep(delay_ms / 1000.0)
        # `sleep` pauses this Ruby thread. Playwright/Ruby's `sleep` takes
        # SECONDS, but our delay is stored in milliseconds, so we divide by
        # 1000.0 (a float, so we get fractional seconds like 2.5 rather than
        # integer division truncating to 2).
      end
      # `end` closes the `locations.each_with_index do |location_data, index|`
      # loop — every location has now been processed.

      log_success("Completed #{company_name}: #{facilities_saved} facilities, #{units_saved} units saved")
      { facilities: facilities_saved, units: units_saved }
      # This Hash literal is the LAST expression evaluated in the `begin`
      # block on the success path, so it becomes the value the whole
      # `begin/rescue/end` expression evaluates to, which in turn is the
      # last expression in `run`, so it becomes `run`'s return value —
      # Ruby methods return whatever their last-evaluated expression is,
      # with no explicit `return` needed.

    rescue Playwright::TimeoutError => e
      # This OUTER rescue (matching the OUTER `begin` that started right
      # after `facilities_saved = 0` / `units_saved = 0`) catches a timeout
      # that happens on the very FIRST page load (the search page itself) —
      # if that fails, we never even got a location list, so there's nothing
      # left to salvage for this company on this run.
      # The initial search page timed out — can't get any locations
      log_error(
        "Timeout on search page for #{company_name}. " \
        "URL: #{search_url(search_lat, search_lng, radius_miles)}. " \
        "Error: #{e.message}"
      )
      { facilities: 0, units: 0, error: e.message }
      # Returns a result Hash that includes an `error:` key so the caller
      # knows this run didn't fully succeed.

    rescue => e
      # Catch-all for unexpected errors — log everything we know
      log_error(
        "Unexpected error crawling #{company_name}: #{e.class}: #{e.message}. " \
        "Full backtrace: #{e.backtrace.join("\n")}"
      )
      # Unlike the inner per-location rescue above (which trims the
      # backtrace to 3 lines), this one joins the ENTIRE backtrace with
      # newlines (`"\n"`) — since this is a crawl-ending failure, we want the
      # full picture in the logs to debug it.
      { facilities: 0, units: 0, error: e.message }
    end
    # `end` closes the OUTERMOST `begin ... rescue ... rescue ... end` block
    # that wraps this entire method's logic.
  end
  # `end` closes the `def run` method definition.

  # ---------------------------------------------------------------------------
  # METHODS THAT SUBCLASSES MUST IMPLEMENT
  # ---------------------------------------------------------------------------

  # Returns the company's full display name
  # Example: "Extra Space Storage"
  def company_name
    # This is the "default" implementation of `company_name` on the base
    # class. It's never meant to actually be used as-is — its ONLY job is to
    # raise an error if a subclass forgets to override it, so mistakes are
    # caught loudly instead of silently returning nothing.
    raise NotImplementedError,
      "#{self.class.name} must implement company_name. " \
      "Return a string like 'Extra Space Storage'."
    # `raise ExceptionClass, "message"` immediately stops execution and
    # throws an error of the given class. `NotImplementedError` is a
    # built-in Ruby exception class meant exactly for this "abstract method,
    # subclass must override me" situation. `self.class.name` reads the name
    # of whichever actual class this code is running as part of — e.g. if
    # some subclass forgot to define `company_name`, this would print that
    # subclass's real name (e.g. "Companies::CubeSmart") in the error, making
    # it obvious which file is missing the method.
  end
  # `end` closes `def company_name`.

  # Returns a short identifier for this company used in file names and logs
  # Example: "extra_space"
  def company_slug
    raise NotImplementedError,
      "#{self.class.name} must implement company_slug. " \
      "Return a short snake_case string like 'extra_space'."
  end
  # `end` closes `def company_slug`. Same "abstract method" pattern as above.

  # Returns the URL to search for locations near the given coordinates
  # Must return a String URL
  def search_url(lat, lng, radius_miles)
    raise NotImplementedError,
      "#{self.class.name} must implement search_url(lat, lng, radius_miles). " \
      "Return the URL the company uses to list nearby locations."
  end
  # `end` closes `def search_url`.

  # Parses the location list from a search results page
  # page: a Playwright page object (you can call page.query_selector etc.)
  # Must return an Array of hashes with these keys:
  #   name:, address:, city:, state:, zip:, phone: (optional), url:
  def parse_locations(page)
    raise NotImplementedError,
      "#{self.class.name} must implement parse_locations(page). " \
      "Return an array of location hashes with keys: name, address, city, state, zip, url."
  end
  # `end` closes `def parse_locations`.

  # Parses unit pricing from a facility's detail page
  # page: a Playwright page object
  # facility: the Facility ActiveRecord object for this location
  # Must return an Array of hashes with unit attributes
  def parse_units(page, facility)
    raise NotImplementedError,
      "#{self.class.name} must implement parse_units(page, facility). " \
      "Return an array of unit attribute hashes."
  end
  # `end` closes `def parse_units`.

  # ---------------------------------------------------------------------------
  # SHARED HELPER METHODS — available to all subclasses via inheritance
  # ---------------------------------------------------------------------------
  protected
  # Everything from here to the end of the class is `protected`: it can only
  # be called from inside this class or a subclass (like cube_smart.rb),
  # never from outside code such as the job/controller that kicks off a
  # crawl. This documents "these are internal building blocks, not part of
  # the public API" and prevents outside code from accidentally depending on
  # them.

  # Processes ONE location from the search-results page: upserts its
  # Facility record, opens its own pricing page, parses/filters/saves its
  # units. Extracted out of `run`'s main loop above (see that loop's
  # REFACTORING NOTE) — this is the unit of work that used to be inlined
  # there.
  #
  # Returns a two-element Array `[facility_saved, units_saved_count]`:
  # `facility_saved` is `true`/`false` (whether this location should count
  # toward the facilities-processed total — false if it had no URL, no
  # units found, or any error occurred), and `units_saved_count` is how
  # many individual units were actually written to the database for this
  # one location (`0` in every failure case). ANY failure for this ONE
  # location (a timeout, a bad parser, a network error) is caught here and
  # turned into `[false, 0]` instead of raising — so one bad location can
  # never stop `run`'s loop from moving on to the next one.
  def process_location(location_data)
    # Find or create the Facility record in the database
    facility = upsert_facility(location_data)
    # "Upsert" = update if it already exists, insert (create) if not.
    # See the `upsert_facility` method further down for details.

    # Visit the facility's pricing page
    facility_page_url = location_data[:url]
    if facility_page_url.blank?
      # `.blank?` is a Rails helper: true for nil, empty string, empty
      # array, whitespace-only string, etc. — a broader check than
      # Ruby's plain `.nil?` or `.empty?`.
      log_warning("No URL for #{location_data[:name]} — skipping unit pricing")
      return [ false, 0 ]
    end
    # `end` closes the `if facility_page_url.blank?` check.

    facility_page = open_page(facility_page_url)
    # Opens a new browser tab at this specific facility's own page
    # (separate from the search-results page opened in `run`).

    # Extract unit data from the facility page
    raw_units = parse_units(facility_page, facility)
    # Calls the SUBCLASS's `parse_units` method with the newly opened
    # facility page and the ActiveRecord `facility` object, returning
    # an Array of raw (unfiltered) unit-attribute Hashes.

    if raw_units.empty?
      log_warning("No units found at #{location_data[:name]}. Page may need updating.")
      take_error_screenshot(facility_page, "no_units_#{facility.id}")
      return [ false, 0 ]
    end
    # `end` closes the `if raw_units.empty?` block above.

    # Step 4: Filter units based on user's filter options
    filtered_units = apply_filters(raw_units)
    # Narrows `raw_units` down to only the ones matching the user's
    # chosen filters (size, climate control, etc.) — see
    # `apply_filters` further down.

    log_info("Found #{raw_units.length} units, #{filtered_units.length} match filters at #{location_data[:name]}")

    # Step 5: Save matching units to the database
    filtered_units.each do |unit_data|
      # Loops over each surviving unit hash (no index needed here, so
      # plain `.each` instead of `.each_with_index`).
      save_unit(unit_data, facility)
      # Writes this unit to the database, associated with the
      # facility — see `save_unit` further down.
    end
    # `end` closes the `filtered_units.each do |unit_data|` loop.

    # This location counts as successfully processed (only reached when
    # raw_units was non-empty) — the caller adds `filtered_units.length`
    # onto its own running units_saved total.
    [ true, filtered_units.length ]

  rescue Playwright::TimeoutError => e
    # This `rescue` clause only catches errors of type
    # `Playwright::TimeoutError` (or subclasses of it) — a specific
    # exception class Playwright raises when a page takes too long to
    # respond. `=> e` captures the actual exception object into a local
    # variable `e` so we can read its message below.
    # Page took too long to load
    log_error(
      "Timeout loading page for #{location_data[:name]}: #{e.message}. " \
      "This can happen on slow connections or slow hardware. Try increasing " \
      "crawl_delay_between_requests_ms in Settings.",
      url: location_data[:url]
    )
    # The trailing `\` at the end of a line lets a Ruby string literal
    # continue onto the next line without inserting a literal newline —
    # it's purely for keeping source lines from getting too long. The
    # two string pieces get concatenated into one long message.
    [ false, 0 ]

  rescue => e
    # A bare `rescue => e` with no exception class after it catches
    # `StandardError` and its subclasses — i.e. "any other normal
    # error we didn't specifically handle above." This must come AFTER
    # the more specific `Playwright::TimeoutError` rescue, because Ruby
    # checks rescue clauses top-to-bottom and uses the first one that
    # matches.
    # Any other error on this specific location — log it and let the
    # caller move on to the next one
    log_error(
      "Error processing #{location_data[:name]}: #{e.class}: #{e.message}. " \
      "Backtrace: #{e.backtrace.first(3).join(' | ')}",
      url: location_data[:url]
    )
    # `e.class` is the exception's Ruby class name (e.g. "NoMethodError"),
    # `e.backtrace` is an Array of Strings describing the call stack
    # where the error happened; `.first(3)` takes just the first 3
    # entries and `.join(' | ')` glues them into one string separated
    # by " | ", so the log stays readable instead of dumping a giant
    # stack trace.
    [ false, 0 ]
  end
  # `end` closes the `def process_location` method definition (including
  # its attached `rescue` clauses).

  # Opens a URL in a new browser page with automatic retry logic
  # Returns the Playwright page object
  def open_page(url, retries: MAX_RETRIES)
    # `retries: MAX_RETRIES` is a keyword argument with a default value —
    # callers can omit it (as `run` does above) to use the `MAX_RETRIES`
    # constant (3), or pass a different number if needed.
    attempt = 0
    # Local counter tracking which attempt we're on, starting at 0.

    begin
      attempt += 1
      log_info("Opening page (attempt #{attempt}/#{retries + 1}): #{url}")
      # `retries + 1` because "3 retries" means up to 4 total attempts (the
      # first try plus 3 retries) — this just makes the log message read
      # correctly.

      # Create a new browser tab
      page = @browser.new_page
      # `@browser` is the shared Playwright browser instance stashed in
      # `initialize`. `.new_page` opens a brand-new tab/page in it and
      # returns an object representing that tab, which we can navigate,
      # query, and screenshot.

      # Set a realistic User-Agent so the site doesn't immediately block us
      page.set_extra_http_headers({
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      })
      # HTTP requests include a "User-Agent" header identifying the
      # browser/client making the request. Playwright's default value can
      # look obviously automated to some sites, so we override it with a
      # string mimicking a normal desktop Chrome browser, making our
      # requests look like an ordinary visitor's rather than a bot. The
      # `{ "User-Agent" => "..." }` is a Ruby Hash literal with one
      # key/value pair, passed as the single argument to
      # `set_extra_http_headers`.

      # Navigate to the URL. We used to wait for "networkidle" here, but modern
      # sites keep background connections open indefinitely (analytics, chat
      # widgets, polling) so network activity never actually goes idle — that
      # made every page load hit the full timeout. "domcontentloaded" fires as
      # soon as the HTML is parsed; each parser's own wait_for_selector call
      # (in parse_locations/parse_units) handles waiting for the real content.
      page.goto(url, waitUntil: "domcontentloaded", timeout: PAGE_TIMEOUT_MS)
      # `.goto(url, ...)` tells the browser tab to navigate to `url`.
      # `waitUntil: "domcontentloaded"` tells Playwright which browser
      # lifecycle event counts as "done navigating" — here, as soon as the
      # raw HTML has been parsed into the page (before all images/scripts
      # necessarily finish). `timeout: PAGE_TIMEOUT_MS` caps how long to wait
      # (30 seconds, per the constant above) before giving up and raising
      # `Playwright::TimeoutError`.

      # Additional wait for any animations or delayed JS rendering
      page.wait_for_timeout(JS_SETTLE_DELAY_MS)
      # An unconditional pause (2 seconds, per the constant) giving
      # JavaScript on the page time to run and finish rendering dynamic
      # content, since `domcontentloaded` alone doesn't guarantee that.

      log_info("Page loaded successfully: #{url}")
      page
      # `page` alone as the last line of this `begin` block means: if we got
      # this far with no exception, the Playwright page object is what this
      # whole `begin/rescue/end` (and therefore the whole method) evaluates
      # to and returns.

    rescue Playwright::TimeoutError => e
      # Handles the case where `.goto` (or something else in the block)
      # timed out.
      if attempt <= retries
        # If we haven't used up all our allowed attempts yet...
        log_warning(
          "Page load timed out (attempt #{attempt}/#{retries + 1}). " \
          "Waiting #{RETRY_DELAY_MS}ms before retry. URL: #{url}"
        )
        sleep(RETRY_DELAY_MS / 1000.0)
        # Pause briefly (3 seconds, converted from ms to seconds) before
        # trying again — gives a temporarily slow/overloaded site a moment
        # to recover.
        retry
        # `retry` is a special Ruby keyword that jumps back to the very
        # start of the enclosing `begin` block and runs it again from
        # scratch (so `attempt += 1` runs again, `page = @browser.new_page`
        # runs again, etc.) — this is literally how the retry loop works,
        # there's no explicit `while` loop here.
      else
        # We've used up all our retries — give up for real.
        log_error(
          "Page load failed after #{retries + 1} attempts. Giving up. " \
          "URL: #{url}. Error: #{e.message}"
        )
        raise  # Re-raise so the caller can handle it
        # A bare `raise` with no arguments, inside a `rescue` block,
        # re-raises the SAME exception that was just caught (`e`) — it
        # propagates up to whichever code called `open_page` (in `run`,
        # above), which has its own rescue clauses to handle it.
      end
      # `end` closes the `if attempt <= retries ... else ... end` branch.

    rescue => e
      # Handles any OTHER kind of error (not a Playwright timeout) that
      # might happen while opening the page — same retry logic applies.
      if attempt <= retries
        log_warning(
          "Unexpected error loading page (attempt #{attempt}/#{retries + 1}): " \
          "#{e.class}: #{e.message}. URL: #{url}"
        )
        sleep(RETRY_DELAY_MS / 1000.0)
        retry
      else
        raise
        # Re-raises after exhausting retries, same as above.
      end
      # `end` closes this `if attempt <= retries ... else ... end` branch.
    end
    # `end` closes the `begin ... rescue ... rescue ... end` block that
    # implements the whole open-with-retries loop.
  end
  # `end` closes `def open_page`.

  # Safely extracts text from a CSS selector on a page
  # Returns nil (not an error) if the element doesn't exist
  # This is much safer than page.query_selector(...).text_content which crashes if nil
  #
  # Usage: safe_text(page, ".price-label")
  def safe_text(page_or_element, selector)
    # `page_or_element` can be either a whole Playwright `page`, OR a smaller
    # already-found element (like one facility "card") — both respond to
    # `.query_selector`, so this method works either way, letting callers
    # search either the whole page or just within one element.
    element = page_or_element.query_selector(selector)
    # Finds the FIRST element matching the CSS `selector` within
    # `page_or_element`. Returns `nil` if nothing matches (Playwright does
    # NOT raise an error for "not found" here — it just returns nil).
    return nil if element.nil?
    # If nothing was found, stop here and return `nil` — this is the whole
    # point of "safe_text": calling `.text_content` on `nil` directly would
    # crash with a `NoMethodError`, so we check first.

    text = element.text_content
    # `.text_content` reads the visible text inside the matched HTML element
    # (stripping out the HTML tags themselves), e.g. for
    # `<span>  $89.00  </span>` it returns "  $89.00  ".
    text&.strip&.presence  # strip whitespace, return nil if empty string
    # `&.` is Ruby's "safe navigation operator" — it calls the following
    # method only if the thing on the left isn't `nil`; if it IS nil, the
    # whole expression short-circuits to `nil` instead of raising an error.
    # Chained here: `.strip` removes leading/trailing whitespace,
    # `.presence` (a Rails helper) returns the string if it's non-empty, or
    # `nil` if it's blank/empty — so callers always get either real text or
    # a clean `nil`, never an empty string like "". This is the LAST
    # expression in the method, so it's the return value.
  rescue => e
    # This `rescue` is attached directly to the `def ... end` method body
    # (no separate `begin` needed — Ruby lets you rescue errors for an
    # entire method this way). Catches ANY unexpected error during the
    # lookup (e.g. the page/tab was already closed) so one bad selector
    # can't crash the whole crawl.
    log_warning("Could not read text from selector '#{selector}': #{e.message}")
    nil
    # Falls back to returning `nil`, consistent with the "not found" case
    # above — callers never need to worry about this method raising.
  end
  # `end` closes `def safe_text`.

  # Safely extracts an attribute value from an element
  # Usage: safe_attr(page, "a.booking-link", "href")
  def safe_attr(page_or_element, selector, attribute)
    element = page_or_element.query_selector(selector)
    return nil if element.nil?

    element.get_attribute(attribute)&.strip&.presence
    # `.get_attribute(attribute)` reads the named HTML attribute (e.g.
    # "href", "data-id") off the matched element, returning its String value
    # or `nil` if that attribute isn't present at all. Same
    # strip/presence-via-safe-navigation cleanup as `safe_text` above.
  rescue => e
    log_warning("Could not read attribute '#{attribute}' from selector '#{selector}': #{e.message}")
    nil
  end
  # `end` closes `def safe_attr`.

  # Safely extracts text from all matching elements (returns an array)
  # Usage: safe_all_text(page, ".unit-row .price")
  def safe_all_text(page_or_element, selector)
    elements = page_or_element.query_selector_all(selector)
    # Unlike `query_selector`, `query_selector_all` finds EVERY matching
    # element and returns them as an Array (an empty Array, never nil, if
    # none match).
    return [] if elements.empty?
    # If there were no matches, return an empty array right away.

    elements.map { |el| el.text_content&.strip&.presence }.compact
    # `.map { |el| ... }` runs the block once per element in `elements` and
    # builds a new Array out of whatever each block call returns — here,
    # each element's cleaned-up text (or nil if it was blank). `{ |el| ... }`
    # is the same kind of block as `do |el| ... end`, just written with curly
    # braces instead — Ruby convention is curly braces for short one-line
    # blocks, `do...end` for longer multi-line ones (as used elsewhere in
    # this file). `.compact` then removes any `nil` entries from that array,
    # so the final result only contains real, non-blank text values.
  rescue => e
    log_warning("Could not read all text from selector '#{selector}': #{e.message}")
    []
    # On error, return an empty array — same "safe" contract as the other
    # helpers: never raises, just returns an empty/nil result.
  end
  # `end` closes `def safe_all_text`.

  # Parse a price string like "$89.00/mo" or "89" into a decimal
  # Returns nil if it can't be parsed
  def parse_price(price_string)
    return nil if price_string.blank?
    # Nothing to parse if we were given nil or an empty/whitespace string.

    # Remove everything except digits and decimal point
    cleaned = price_string.to_s.gsub(/[^\d.]/, "")
    # `.to_s` ensures we're working with a String even if something odd was
    # passed in. `.gsub(pattern, replacement)` replaces every match of
    # `pattern` with `replacement` (global substitute — "g" = all
    # occurrences, not just the first). The pattern `/[^\d.]/` is a regular
    # expression (regex): `[...]` is a "character class" matching any ONE of
    # the characters listed inside; `^` as the FIRST character inside `[...]`
    # negates it, meaning "any character that is NOT one of these"; `\d`
    # means "a digit (0-9)"; `.` inside a character class is a literal dot,
    # not "any character" (that special meaning of `.` only applies outside
    # `[...]`). So this regex matches any character that is neither a digit
    # nor a dot, and replaces each one with `""` (nothing) — effectively
    # stripping out currency symbols, commas, "/mo", spaces, etc., leaving
    # just something like "89.00".
    return nil if cleaned.blank?
    # If after stripping there's nothing left (e.g. input was just "$" with
    # no numbers), bail out with nil.

    price = cleaned.to_f
    # `.to_f` converts the cleaned numeric string into a Float (a
    # floating-point/decimal number), e.g. "89.00" -> 89.0.
    return nil if price <= 0
    # A price of zero or negative doesn't make sense for a storage unit —
    # treat it as "couldn't parse a real price."

    price.round(2)
    # Rounds to 2 decimal places (cents) and returns that as the method's
    # result, since this is the last expression evaluated.
  rescue => e
    log_warning("Could not parse price from '#{price_string}': #{e.message}")
    nil
  end
  # `end` closes `def parse_price`.

  # Parse a size string like "10' x 20'" or "10X20" into normalized "10x20" format
  def parse_size(size_string)
    return nil if size_string.blank?

    # Extract just the numbers — handles formats like "10x20", "10' x 20'", "10 X 20 ft"
    numbers = size_string.to_s.scan(/\d+/).map(&:to_i)
    # `.scan(/\d+/)` finds every run of one-or-more digits (`\d+`) in the
    # string and returns them all as an Array of Strings, e.g. "10' x 20'"
    # -> ["10", "20"]. `.map(&:to_i)` then converts each of those strings to
    # an Integer. `&:to_i` is shorthand for `{ |s| s.to_i }` — the `&` turns
    # the symbol `:to_i` into something `.map` can call as a block, applying
    # that one method to every element.

    # We need exactly two numbers (width and depth)
    return nil unless numbers.length >= 2
    # `unless` is Ruby's inverted `if` — this line means "return nil IF NOT
    # (numbers.length >= 2)", i.e. bail out unless we found at least two
    # numbers (some formats might have a stray extra number like "10x20 ft2",
    # so we only require AT LEAST two, and use just the first two below).

    "#{numbers[0]}x#{numbers[1]}"
    # Builds and returns a normalized string like "10x20" from the first two
    # numbers found, regardless of how the original was formatted (quotes,
    # spaces, capital X, etc).
  rescue => e
    log_warning("Could not parse size from '#{size_string}': #{e.message}")
    nil
  end
  # `end` closes `def parse_size`.

  # Takes a screenshot and saves it to the logs directory
  # Used automatically when errors occur so you can see what went wrong
  def take_error_screenshot(page, label)
    filename = "logs/#{company_slug}_#{label}_#{Time.current.strftime("%Y%m%d_%H%M%S")}.png"
    # Builds a filename like "logs/cubesmart_no_cards_20260722_143012.png" —
    # `Time.current` (a Rails helper, timezone-aware version of `Time.now`)
    # gives the current timestamp, and `.strftime("%Y%m%d_%H%M%S")` formats
    # it as Year-Month-Day_Hour-Minute-Second so filenames sort chronologically
    # and never collide between runs.

    begin
      page.screenshot(path: Rails.root.join(filename).to_s)
      # `.screenshot(path: ...)` tells Playwright to capture an image of the
      # current page and save it to disk. `Rails.root` is the absolute path
      # to this Rails app's root folder; `.join(filename)` appends our
      # relative "logs/..." path onto it to get a full absolute path, and
      # `.to_s` converts that Pathname object into a plain String (which is
      # what Playwright's API expects).
      log_info("Error screenshot saved: #{filename}")
    rescue => e
      log_warning("Could not save screenshot: #{e.message}")
      # If even taking the screenshot fails (e.g. the page/tab already
      # closed), don't let that crash the crawl either — just log it.
    end
    # `end` closes this inner `begin ... rescue ... end`.
  end
  # `end` closes `def take_error_screenshot`.

  # Find or create a Facility record from location data
  # Uses external_id or (company + address) as the unique identifier
  def upsert_facility(location_data)
    # Try to find an existing facility by external_id first (most reliable)
    facility = if location_data[:external_id].present?
      # An `if/else` expression can be assigned directly to a variable in
      # Ruby — whichever branch runs, its last-evaluated line becomes the
      # value assigned to `facility`. `.present?` is the opposite of
      # `.blank?` (true when there IS real/non-empty content).
      Facility.find_or_initialize_by(
        company:     company_name,
        external_id: location_data[:external_id]
      )
      # `Facility` is an ActiveRecord model (Rails' database wrapper class)
      # representing the `facilities` database table.
      # `.find_or_initialize_by(company: ..., external_id: ...)` looks for an
      # existing row matching BOTH of those column values; if found, returns
      # that existing record (not yet saved again); if not found, builds a
      # new, unsaved Facility object with those attributes pre-filled. Using
      # the company's own external_id (when they expose one) is the most
      # reliable way to recognize "this is the same facility we saw before."
    else
      # Fall back to matching on company + address (less reliable but still works)
      Facility.find_or_initialize_by(
        company: company_name,
        address: location_data[:address],
        city:    location_data[:city],
        state:   location_data[:state]
      )
      # When the company doesn't expose a stable ID, fall back to matching on
      # company name + street address + city + state as a "close enough"
      # unique identifier.
    end
    # `end` closes the `if/else` expression whose result was assigned to
    # `facility`.

    # Update all fields (whether new or existing record)
    facility.assign_attributes(
      name:         location_data[:name]         || "#{company_name} - #{location_data[:city]}",
      # `||` is Ruby's "or" operator; used here as a fallback: if
      # `location_data[:name]` is falsy (nil or false), use the string on
      # the right instead (e.g. "CubeSmart - Gilbert") as a default name.
      address:      location_data[:address],
      city:         location_data[:city],
      state:        location_data[:state],
      zip:          location_data[:zip],
      phone:        location_data[:phone],
      facility_url: location_data[:url],
      external_id:  location_data[:external_id]
    )
    # `.assign_attributes(...)` sets all these columns on the in-memory
    # `facility` object (whether it's a brand-new record or one we just
    # fetched from the database) WITHOUT saving to the database yet — so
    # every crawl refreshes the facility's info (phone, address, etc.) even
    # for facilities we've seen before.

    if facility.save
      # `.save` writes the object to the database (INSERT if new, UPDATE if
      # existing) and returns `true` on success or `false` if validation
      # failed (e.g. a required field was missing).
      facility
      # On success, this branch's (and therefore the method's) return value
      # is the saved `facility` object.
    else
      # If save fails, log what went wrong and raise so the caller knows
      error_messages = facility.errors.full_messages.join(", ")
      # `.errors` is an ActiveRecord object holding validation failure
      # details after a failed save; `.full_messages` turns them into
      # human-readable strings (e.g. "Address can't be blank"), and `.join`
      # combines them into one comma-separated string for the error message.
      raise "Could not save facility '#{location_data[:name]}': #{error_messages}"
      # `raise "some string"` raises a generic `RuntimeError` with that
      # string as its message — this propagates up to the `rescue` clauses
      # in `run` (the per-location `begin/rescue`), which will log it and
      # move on to the next location rather than crashing the whole crawl.
    end
    # `end` closes the `if facility.save ... else ... end` branch.
  end
  # `end` closes `def upsert_facility`.

  # Save a unit to the database associated with a facility and the current crawl run
  def save_unit(unit_data, facility)
    unit = Unit.new(
      facility:    facility,
      crawl_run:   @crawl_run,
      collected_at: Time.current,
      **unit_data  # Spread all the unit attributes from the hash
    )
    # `Unit.new(...)` builds a new (unsaved) ActiveRecord `Unit` object.
    # `**unit_data` is Ruby's "double-splat" operator: it takes every
    # key/value pair out of the `unit_data` Hash (size:, monthly_price:,
    # etc., as built by each company's `parse_units`) and passes them all as
    # individual keyword arguments here — equivalent to writing out
    # `size: unit_data[:size], monthly_price: unit_data[:monthly_price], ...`
    # by hand for every key, but far shorter and automatically stays correct
    # if new keys get added to unit_data later.

    unless unit.save
      # `unless` again = "if not" — this block runs only when `.save`
      # returns false (failed).
      error_messages = unit.errors.full_messages.join(", ")
      log_warning(
        "Could not save unit (#{unit_data[:size]} at #{facility.name}): #{error_messages}"
      )
      # Unlike `upsert_facility`, a failed unit save only logs a WARNING
      # (not a raised error) — one bad unit shouldn't stop the rest of the
      # units at this facility from being saved.
    end
    # `end` closes the `unless unit.save` block.

    unit
    # Returns the `unit` object regardless of whether the save actually
    # succeeded (callers in `run` don't currently use this return value, but
    # returning it keeps the method's behavior predictable/inspectable).
  end
  # `end` closes `def save_unit`.

  # Filter raw unit data through the user's filter options
  # Returns only units that match
  def apply_filters(raw_units)
    # What sizes did the user select?
    selected_sizes = @options[:sizes] || Unit::DEFAULT_SIZES
    # If the user's crawl options included specific sizes, use those;
    # otherwise fall back to `Unit::DEFAULT_SIZES` — a constant defined on
    # the `Unit` model (accessed here via `Unit::DEFAULT_SIZES`, where `::`
    # is how Ruby reaches a constant defined inside another
    # class/module).

    # What unit types to exclude?
    excluded_types = @options[:excluded_types] || Unit::EXCLUDED_TYPES

    raw_units.select do |unit|
      # `.select do |unit| ... end` (also spelled `.filter` in Ruby) builds a
      # NEW array containing only the elements from `raw_units` for which the
      # block returns a truthy value. Each `unit` here is one Hash of raw
      # unit attributes, as produced by a subclass's `parse_units`.
      # Must be climate controlled (if filter is on)
      next false if @options[:climate_controlled] && !unit[:climate_controlled]
      # Inside a `.select`/`.each`/etc. block, `next value` works like
      # `return value` for a normal method — it immediately ends this one
      # iteration of the block with `value` as the block's result (here,
      # `false`, meaning "exclude this unit"), then moves on to the next
      # unit. So: if the user turned ON the climate-controlled filter AND
      # this particular unit is NOT climate controlled, exclude it.

      # Must not be an excluded type (parking, RV, boat, locker, etc. — see
      # Unit::EXCLUDED_TYPES). Note: we do NOT hard-exclude drive-up/outdoor
      # units here — there's no UI control for that, so silently dropping
      # them just loses real inventory the user asked to see.
      next false if excluded_types.include?(unit[:unit_type].to_s.downcase)
      # Excludes this unit if its `unit_type` (lower-cased, converted to a
      # String defensively with `.to_s` in case it's nil) appears in the
      # excluded-types list (e.g. "parking", "rv", "locker").

      # Must match one of the selected sizes
      size = parse_size(unit[:size].to_s)
      next false unless size
      # Re-normalizes the unit's size string through `parse_size` (defined
      # above); if it can't be parsed into a valid "WxD" size at all,
      # exclude the unit (`unless size` means "if size is falsy/nil").

      parts = size.split("x").map(&:to_i)
      # Splits the normalized "10x20" string on the literal "x" character,
      # giving ["10", "20"], then converts each piece to an Integer.
      next false unless parts.length == 2
      # Defensive check — should always be exactly 2 pieces given how
      # `parse_size` builds its output, but guards against any edge case.

      width, depth = parts
      # "Multiple assignment": unpacks the two-element `parts` array into two
      # separate local variables in one line — equivalent to
      # `width = parts[0]; depth = parts[1]`.
      min_width = 10
      min_depth  = 10
      # (Note the extra space before `= 10` on this line is just how the
      # original code was formatted — doesn't change behavior.)

      next false if width < min_width || depth < min_depth
      # Excludes units smaller than the site's practical minimum (10 feet in
      # either dimension) — these are treated as too small/likely lockers
      # rather than real filterable storage sizes.

      # If specific sizes are selected, include this unit if it belongs to
      # the closest selected size bucket. Real listings come in far more
      # granular sizes than the 5 standard checkboxes (10x12, 10x24, 12x20,
      # ...) — matching the *exact* string would silently drop almost
      # everything that isn't precisely "10x10"/"10x15"/etc. Bucketing by
      # square footage keeps every unit >= 10x10 visible under whichever
      # standard size it's closest to.
      if selected_sizes.present?
        # Only apply this size-bucket restriction if the user actually
        # selected specific sizes (an empty/absent selection means "show all
        # sizes").
        next false unless selected_sizes.include?(size_bucket(width, depth))
        # `size_bucket` (defined right below) maps this unit's actual
        # dimensions to whichever "standard" size (from the 5 checkbox
        # options) it's closest to by area — exclude the unit unless that
        # bucket is one the user selected.
      end
      # `end` closes the `if selected_sizes.present?` block.

      true  # This unit passes all filters
      # If none of the `next false` lines above triggered, this is the last
      # expression evaluated for this unit, so `.select` treats it as "keep
      # this unit" (any non-`false`/non-`nil` value counts as truthy in
      # Ruby, but `true` is used explicitly here for clarity).
    end
    # `end` closes the `raw_units.select do |unit| ... end` block. The
    # resulting filtered array is this whole `.select` call's value, which
    # is also the last expression in the method, so it's `apply_filters`'
    # return value.
  end
  # `end` closes `def apply_filters`.

  # Maps an arbitrary WxD unit size to the closest of Unit::DEFAULT_SIZES,
  # by comparing square footage. e.g. a real 10x12 (120 sqft) is closer to
  # 10x10 (100 sqft) than 10x15 (150 sqft), so it buckets as "10x10".
  def size_bucket(width, depth)
    sqft = width * depth
    # Computes this unit's area in square feet by multiplying its two
    # dimensions.

    Unit::DEFAULT_SIZES.min_by do |standard_size|
      # `Unit::DEFAULT_SIZES` is presumably an Array of standard size
      # strings like ["5x5", "5x10", "10x10", "10x15", "10x20"].
      # `.min_by do |el| ... end` returns whichever ELEMENT of the array
      # produces the SMALLEST value when passed through the block — here,
      # it finds the standard size string whose own square footage is
      # closest (in absolute difference) to this unit's actual square
      # footage.
      sw, sd = standard_size.split("x").map(&:to_i)
      # Parses each standard size string (e.g. "10x15") into its own width
      # (sw) and depth (sd) integers, same splitting technique as in
      # `apply_filters` above.
      (sqft - (sw * sd)).abs
      # Computes the absolute difference in area between this unit's real
      # square footage and this standard size's square footage — `.abs`
      # makes negative differences positive, since we only care about how
      # far apart they are, not which direction. This is the block's
      # return value, which `.min_by` uses to decide which standard_size
      # "wins" (smallest area-difference).
    end
    # `end` closes the `Unit::DEFAULT_SIZES.min_by do |standard_size| ... end`
    # block. Its result (the closest-matching standard size string) is the
    # last expression in the method, so it's `size_bucket`'s return value.
  end
  # `end` closes `def size_bucket`.

  # ---------------------------------------------------------------------------
  # LOGGING HELPERS — delegate to the CrawlRun model's log methods
  # ---------------------------------------------------------------------------
  # These four tiny methods all follow the same pattern: they exist so the
  # rest of this file (and every subclass) can just write `log_info("...")`
  # instead of the longer `@crawl_run.log_info("...", company: company_name)`
  # every single time — a small but very common convenience wrapper. Each one
  # "delegates" (hands off) the actual work to a method of the same name on
  # the `CrawlRun` ActiveRecord model, which presumably writes the message to
  # a database-backed crawl log the UI can display, tagging every entry with
  # which company and (optionally) which URL it came from.

  def log_info(message, url: nil)
    # `url: nil` is a keyword argument with a default of `nil` — callers can
    # omit it entirely (as most calls to `log_info` in this file do).
    @crawl_run.log_info(message, company: company_name, url: url)
  end
  # `end` closes `def log_info`.

  def log_warning(message, url: nil, retry_count: 0)
    @crawl_run.log_warning(message, company: company_name, url: url, retry_count: retry_count)
  end
  # `end` closes `def log_warning`.

  def log_error(message, url: nil, retry_count: 0)
    @crawl_run.log_error(message, company: company_name, url: url, retry_count: retry_count)
  end
  # `end` closes `def log_error`.

  def log_success(message, url: nil)
    @crawl_run.log_success(message, company: company_name, url: url)
  end
  # `end` closes `def log_success`.
end
# `end` closes the `class Companies::BaseParser` definition that started at
# the very top of the file.
