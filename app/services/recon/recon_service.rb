# =============================================================================
# RECON SERVICE
# =============================================================================
# Auto-inspects any storage company website and generates a report containing:
#   - Screenshot of the page
#   - All CSS selectors that look like they could contain prices, names, addresses
#   - The page's full HTML structure (simplified)
#   - A JSON summary of what was found
#
# This is used to build new company parsers WITHOUT having to manually inspect
# the site in a browser.
#
# Usage (from Rails console or a rake task):
#   ReconService.run("https://www.cubesmart.com/storage-units/az/gilbert/")
#
# Output goes to:
#   recon/cubesmart_20240115_143200_report.txt     (human readable)
#   recon/cubesmart_20240115_143200_screenshot.png (what the page looks like)
#   recon/cubesmart_20240115_143200_data.json      (structured selector data)
# =============================================================================

# A plain-Ruby "service object" (see app/services/company_registry.rb for a
# full explanation) — a class that isn't a database model or web
# controller, dedicated instead to one task: driving a real browser to
# visit a storage company's website and dump out everything that looks
# potentially useful for a human (or an AI) to then write a proper parser
# for that site.
#
# This class is meant to be run manually (from a Rails console or a rake
# task), not as part of the normal crawl flow — it's a developer tool.
class ReconService
  # Patterns we use to find "interesting" elements on the page
  # These are guesses that work on most storage websites
  #
  # Each of these constants is a Ruby REGULAR EXPRESSION (regex) — a
  # pattern used to test whether a piece of text matches certain rules.
  # Regex literals in Ruby are written between forward slashes `/like
  # this/`. Below is a breakdown of the regex syntax used in each pattern:
  #   \d       — matches any single digit (0-9)
  #   \b       — a "word boundary": matches the edge between a word
  #              character and a non-word character (e.g. right before or
  #              after a whole word), so `\bprice\b` matches the standalone
  #              word "price" but NOT "priceless" or "unpriced"
  #   |        — "or": matches if EITHER side of the pipe matches
  #   [x×]     — a "character class": matches any ONE of the characters
  #              listed inside the brackets (here, either a lowercase x or
  #              the multiplication sign ×, as in "10x10" or "10×10")
  #   +        — "one or more" of whatever came immediately before it
  #   i        — a trailing flag (outside the closing slash) meaning
  #              "case-insensitive": matches regardless of upper/lower case
  #
  # PRICE_PATTERNS matches text containing a dollar sign followed by a
  # digit, or the standalone words "price," "rate," "month," or "mo."
  PRICE_PATTERNS     = /\$\d|\bprice\b|\brate\b|\bmonth\b|\bmo\b/i
  # SIZE_PATTERNS matches things like "10x10" or "10×10" (unit dimensions),
  # or the words "size," "dimension," "width," or "depth."
  SIZE_PATTERNS      = /\d+[x×]\d+|\bsize\b|\bdimension\b|\bwidth\b|\bdepth\b/i
  # ADDRESS_PATTERNS matches common address/contact-related words.
  ADDRESS_PATTERNS   = /\baddress\b|\bstreet\b|\bcity\b|\bstate\b|\bzip\b|\bphone\b/i
  # FACILITY_PATTERNS matches words that suggest a storage facility/location listing.
  FACILITY_PATTERNS  = /\bfacility\b|\blocation\b|\bstore\b|\bstorage\b|\bresult\b/i
  # UNIT_PATTERNS matches words describing an individual storage unit.
  # `\bstorage.unit\b` — note the `.` here (not escaped as `\.`) matches
  # ANY single character between "storage" and "unit" (not just a literal
  # period), so it matches "storage unit," "storage-unit," "storage.unit," etc.
  UNIT_PATTERNS      = /\bunit\b|\bspace\b|\broom\b|\bstorage.unit\b/i
  # LINK_PATTERNS matches words commonly found on "book this unit" buttons/links.
  LINK_PATTERNS      = /\breserve\b|\brent\b|\bbook\b|\bdetail\b|\bview\b/i

  # ---------------------------------------------------------------------------
  # CLASS METHOD — the main entry point
  # ---------------------------------------------------------------------------
  # `company_name: nil` is a keyword argument with a default value of nil
  # — callers may omit it, in which case the class will try to guess a
  # company name from the URL itself (see extract_company_name below).
  def self.run(url, company_name: nil)
    # Same convenience pattern seen in the other service objects in this
    # app: build a real instance, then call the instance method of the
    # same name on it.
    new(url, company_name: company_name).run
  end
  # `end` closes the `def self.run` class method definition above.

  # ---------------------------------------------------------------------------
  # INITIALIZER
  # ---------------------------------------------------------------------------
  def initialize(url, company_name: nil)
    @url          = url
    # `company_name || extract_company_name(url)` — use the explicitly
    # passed-in name if given, otherwise fall back to guessing one from
    # the URL by calling the private method defined near the bottom of
    # this file.
    @company_name = company_name || extract_company_name(url)
    # `Time.current` is Rails' timezone-aware "now." `.strftime(...)`
    # formats it into a compact string like "20260722_154500" (year, month,
    # day, underscore, hour, minute, second) suitable for use in a
    # filename, since filenames can't contain most punctuation/spaces.
    @timestamp    = Time.current.strftime("%Y%m%d_%H%M%S")
    # `Rails.root.join("recon")` builds a full filesystem path to a
    # "recon" folder inside this Rails app's root directory — `Rails.root`
    # is Rails' way of finding the app's own top-level directory
    # regardless of what the current working directory happens to be.
    @output_dir   = Rails.root.join("recon")

    # Create output directory if it doesn't exist
    #
    # `FileUtils.mkdir_p` is Ruby's standard-library equivalent of the
    # shell command `mkdir -p` — it creates the given directory (and any
    # missing parent directories) and does NOT raise an error if the
    # directory already exists (unlike plain `mkdir`).
    FileUtils.mkdir_p(@output_dir)

    # Base name for all output files
    #
    # Builds a shared filename prefix (without extension) that every
    # output file for this recon run will share, so they're easy to spot
    # together in a directory listing. `@company_name.downcase` lowercases
    # it; `.gsub(/\W+/, "_")` uses another regex — `\W` means "any
    # NON-word character" (i.e., anything that ISN'T a letter, digit, or
    # underscore, like spaces or punctuation) and `+` means "one or more
    # in a row" — replacing any run of such characters with a single
    # underscore, so a company name like "U-Haul Self-Storage" becomes
    # something filesystem-safe like "u_haul_self_storage".
    @base_filename = "#{@output_dir}/#{@company_name.downcase.gsub(/\W+/, "_")}_#{@timestamp}"
  end
  # `end` closes the `def initialize` method definition above.

  # ---------------------------------------------------------------------------
  # RUN
  # ---------------------------------------------------------------------------
  def run
    # `puts` prints a line of text directly to the console/terminal output
    # (as opposed to Rails.logger, which writes to the app's log file) —
    # appropriate here since this is a developer-run console tool meant to
    # show live progress to whoever is running it.
    puts ""
    # `"=" * 70` is Ruby's String repetition operator: it builds a new
    # string consisting of the character "=" repeated 70 times, used here
    # purely as a visual divider line in the console output.
    puts "=" * 70
    puts "STORAGEFINDER RECON TOOL"
    puts "=" * 70
    puts "URL:     #{@url}"
    puts "Company: #{@company_name}"
    puts "Output:  #{@output_dir}"
    puts ""
    puts "Launching browser..."

    # Backticks `` `...` `` run a shell command and capture whatever it
    # printed to standard output as a Ruby String. `timeout 10 which
    # playwright` runs the `which` command (locates an executable on the
    # system PATH) for "playwright," but wrapped in the `timeout` coreutil
    # so it can't hang forever if something's wrong with the shell
    # environment; `10` is the max seconds to wait. `2>/dev/null` (shell
    # syntax, not Ruby) discards any error output so it doesn't leak into
    # the captured string. `.strip` removes leading/trailing whitespace
    # (like a trailing newline) from the captured output.
    playwright_path = `timeout 10 which playwright 2>/dev/null`.strip
    # `.blank?` — the Rails helper meaning nil-or-empty — checks whether
    # the `which` command found nothing. If so, fall back to just the bare
    # string "playwright" and let Playwright itself raise a clear error if
    # that turns out not to be runnable either (rather than trying to
    # replicate the same npx-fallback logic CrawlJob uses).
    playwright_path = "playwright" if playwright_path.blank?  # fallback, let it fail with a clear error

    # `Playwright.create(...) do |playwright| ... end` is provided by the
    # `playwright-ruby-client` gem. It starts up a connection to a
    # Playwright driver process (using the executable path found above)
    # and yields a `playwright` object you can use to control a browser.
    # When the block finishes (or raises), Playwright automatically shuts
    # that driver process down — similar to how Ruby's `File.open(...) do
    # |f| ... end` automatically closes the file afterward.
    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      # `.chromium.launch(...)` starts an actual Chromium (Chrome-like)
      # browser process, configured by the options below.
      browser = playwright.chromium.launch(
        headless: false,  # Visible so you can see what the recon tool is doing
        # `headless: false` means the browser window is actually shown on
        # screen (as opposed to CrawlJob's browser, which typically runs
        # "headless" — invisible, with no window — for efficiency). Seeing
        # the browser is useful here since a human developer is actively
        # watching this tool run to understand a new site.
        args: [ "--window-size=1280,900" ]
        # `args:` passes extra command-line flags to the underlying
        # Chromium process — here, just setting its window size.
      )

      # `browser.new_page` opens a new browser tab/page — most Playwright
      # actions (navigating, clicking, reading content) happen through
      # this `page` object rather than the `browser` object directly.
      page = browser.new_page
      page.set_viewport_size(width: 1280, height: 900)

      # Set a realistic User-Agent
      #
      # The User-Agent HTTP header tells a website what browser/OS is
      # visiting it. Some sites block or behave differently for requests
      # that don't look like a real desktop browser (e.g. blocking
      # automated/headless browser signatures), so this spoofs a common,
      # ordinary-looking Chrome-on-Windows user agent string.
      page.set_extra_http_headers({
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      })

      # `begin ... rescue ... ensure ... end` — this block runs the actual
      # page visit and data extraction. `rescue` clauses catch specific
      # error types if something goes wrong, and `ensure` (below) runs
      # NO MATTER WHAT — whether the block succeeded, raised a caught
      # error, or even an uncaught one — guaranteeing the browser gets
      # closed either way.
      begin
        puts "Loading page..."
        # `page.goto(url, waitUntil: ..., timeout: ...)` navigates the
        # browser to the target URL. `waitUntil: "domcontentloaded"` tells
        # Playwright to consider the navigation "done" once the page's
        # basic HTML structure has loaded (not necessarily every image or
        # background script). `timeout: 30_000` is the max time to wait,
        # in milliseconds (the underscore in `30_000` is just a Ruby
        # readability separator for large numbers — it's parsed identically
        # to `30000`) — 30 seconds.
        page.goto(@url, waitUntil: "domcontentloaded", timeout: 30_000)

        # Wait a bit for lazy-loaded content to appear
        #
        # Many modern sites load some content (like unit listings) via
        # JavaScript AFTER the initial page load finishes — this pauses
        # for a fixed 3000 milliseconds (3 seconds) to give that content
        # time to appear before we start scanning the page.
        page.wait_for_timeout(3000)
        puts "Page loaded."

        # -----------------------------------------------------------------------
        # 1. Screenshot
        # -----------------------------------------------------------------------
        screenshot_path = "#{@base_filename}_screenshot.png"
        # `page.screenshot(path: ..., fullPage: true)` saves an image of
        # the current page to disk at `screenshot_path`. `fullPage: true`
        # captures the entire scrollable page, not just what's currently
        # visible in the viewport.
        page.screenshot(path: screenshot_path, fullPage: true)
        puts "✓ Screenshot saved: #{screenshot_path}"

        # -----------------------------------------------------------------------
        # 2. Extract all interesting elements and their selectors
        # -----------------------------------------------------------------------
        puts "Scanning page structure..."
        # Calls the big private method below that does all the actual
        # element-scanning work and returns a Hash of findings.
        findings = scan_page(page)

        # -----------------------------------------------------------------------
        # 3. Write JSON data file
        # -----------------------------------------------------------------------
        json_path = "#{@base_filename}_data.json"
        # `JSON.pretty_generate(findings)` converts the findings Hash into
        # a nicely-indented, human-readable JSON string (as opposed to
        # `JSON.generate`, used elsewhere in this codebase, which produces
        # compact single-line JSON). `File.write(path, content)` writes
        # that string out to disk as a new file (or overwrites an existing
        # one at that path).
        File.write(json_path, JSON.pretty_generate(findings))
        puts "✓ JSON data saved: #{json_path}"

        # -----------------------------------------------------------------------
        # 4. Write human-readable report
        # -----------------------------------------------------------------------
        # Turns the same findings Hash into a plain-text report (see
        # build_report below) meant for a human to skim quickly, rather
        # than the more machine-oriented JSON file above.
        report = build_report(findings)
        report_path = "#{@base_filename}_report.txt"
        File.write(report_path, report)
        puts "✓ Report saved: #{report_path}"

        # Print a quick summary to the console
        puts ""
        puts "=" * 70
        # `.upcase` converts the company name string to all uppercase
        # letters, purely for visual emphasis in this console banner.
        puts "RECON SUMMARY FOR #{@company_name.upcase}"
        puts "=" * 70
        puts report
        puts ""
        puts "Share the recon/ folder contents with Claude to get a real parser written."

      rescue Playwright::TimeoutError => e
        # Specifically catches the case where `page.goto` (or another
        # Playwright wait) exceeded its timeout — usually meaning the site
        # is slow, unreachable, or blocking automated browsers.
        puts "ERROR: Page timed out loading #{@url}"
        puts "Details: #{e.message}"
        puts "Try opening the URL manually in a browser to check if it's accessible."

      rescue => e
        # Catch-all for any other unexpected StandardError during the
        # visit/scan.
        puts "ERROR: #{e.class}: #{e.message}"
        # `e.backtrace` is an array of strings describing the call stack
        # at the moment the error was raised (which method called which,
        # down to file/line numbers) — useful for debugging. `.first(5)`
        # takes just the first 5 entries (the most immediately relevant
        # ones) rather than dumping the whole (potentially huge) stack.
        puts e.backtrace.first(5).join("\n")

      ensure
        # Runs unconditionally after the begin block, whether it succeeded
        # or hit one of the rescue clauses above — guarantees the browser
        # process gets shut down and doesn't linger running in the
        # background even if something above failed.
        browser.close
      end
      # `end` closes the `begin/rescue/ensure` block above.
    end
    # `end` closes the `Playwright.create(...) do |playwright|` block —
    # this is also where Playwright shuts down its driver process.
  end
  # `end` closes the `def run` method definition above.

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  # Scan the page for elements that look relevant to storage unit data
  def scan_page(page)
    # Builds the Hash that will hold every category of finding. Starting
    # with placeholder empty arrays/hashes/nil values makes the intended
    # shape of the final result clear up front, before each section below
    # fills its own key in.
    findings = {
      url:           @url,
      company:       @company_name,
      timestamp:     @timestamp,
      # `page.title` reads the HTML page's `<title>` tag content directly
      # from the live browser page.
      page_title:    page.title,
      price_elements:    [],
      size_elements:     [],
      address_elements:  [],
      facility_containers: [],
      unit_containers:   [],
      booking_links:     [],
      all_classes_with_counts: {},
      data_attributes:   [],
      pagination:        nil,
      possible_api_urls: []
    }

    # -------------------------------------------------------------------------
    # Find price-related elements
    # -------------------------------------------------------------------------
    # Calls the shared `extract_elements` helper (defined below) with the
    # PRICE_PATTERNS regex constant, capping results at 20 matches, and
    # stores the returned array under the `:price_elements` key.
    findings[:price_elements] = extract_elements(page, PRICE_PATTERNS, limit: 20)

    # -------------------------------------------------------------------------
    # Find size-related elements
    # -------------------------------------------------------------------------
    findings[:size_elements] = extract_elements(page, SIZE_PATTERNS, limit: 20)

    # -------------------------------------------------------------------------
    # Find address/contact elements
    # -------------------------------------------------------------------------
    findings[:address_elements] = extract_elements(page, ADDRESS_PATTERNS, limit: 20)

    # -------------------------------------------------------------------------
    # Find facility/location containers (likely the repeating result cards)
    # -------------------------------------------------------------------------
    # Uses the different `find_containers` helper (below), which looks for
    # REPEATED elements (like a grid of facility cards) rather than
    # individual text snippets.
    findings[:facility_containers] = find_containers(page, FACILITY_PATTERNS, limit: 5)

    # -------------------------------------------------------------------------
    # Find unit containers
    # -------------------------------------------------------------------------
    findings[:unit_containers] = find_containers(page, UNIT_PATTERNS, limit: 5)

    # -------------------------------------------------------------------------
    # Find booking/reserve links
    # -------------------------------------------------------------------------
    findings[:booking_links] = extract_links(page, LINK_PATTERNS, limit: 10)

    # -------------------------------------------------------------------------
    # Collect all CSS classes used on the page with their frequency
    # This helps us find the repeating element patterns (like unit cards)
    # -------------------------------------------------------------------------
    findings[:all_classes_with_counts] = collect_css_classes(page)

    # -------------------------------------------------------------------------
    # Find all data-* attributes (modern React/Vue apps use these heavily)
    # -------------------------------------------------------------------------
    findings[:data_attributes] = collect_data_attributes(page)

    # -------------------------------------------------------------------------
    # Check for pagination
    # -------------------------------------------------------------------------
    # `page.query_selector(...)` runs a CSS selector against the live page
    # and returns the FIRST matching element (or nil if none match). The
    # selector string here is several alternatives separated by commas
    # (standard CSS syntax for "match ANY of these"): a class named
    # "pagination," an element with `aria-label="pagination"` (an
    # accessibility attribute), a class named "pager," a `<nav>` element
    # marked with `role="navigation"`, or a class named "load-more."
    pagination_el = page.query_selector(
      ".pagination, [aria-label='pagination'], .pager, nav[role='navigation'], .load-more"
    )
    # A ternary: if something matched, record that pagination exists along
    # with a description of the element; otherwise record that it doesn't.
    findings[:pagination] = pagination_el ? {
      exists:   true,
      selector: describe_element(pagination_el)
    } : { exists: false }

    # The findings Hash, now fully populated, is the last expression
    # evaluated — so it's this method's return value.
    findings
  end
  # `end` closes the `def scan_page` method definition above.

  # Extract elements whose text matches a pattern
  def extract_elements(page, pattern, limit: 20)
    results = []

    # Get all text-containing elements
    #
    # `page.query_selector_all(...)` runs a CSS selector and returns EVERY
    # matching element (unlike query_selector, which returns just the
    # first). This selector lists many common text-holding HTML tags
    # (paragraphs, spans, divs, table cells, list items, headings, labels)
    # PLUS any element whose `class` attribute contains the substring
    # "price," "size," or "rate" (`[class*='price']` is a CSS "attribute
    # contains" selector).
    all_elements = page.query_selector_all("p, span, div, td, li, h1, h2, h3, h4, label, [class*='price'], [class*='size'], [class*='rate']")

    # `.each do |el| ... end` loops over every matched element.
    all_elements.each do |el|
      # `break` here exits the loop entirely once we've already collected
      # `limit` results — no point continuing to scan the rest of a
      # possibly huge page once we have enough matches.
      break if results.length >= limit

      # Wrapping each element's inspection in its own begin/rescue means
      # one problematic element (e.g. one that's been removed from the
      # page by the time we inspect it) doesn't abort scanning the rest.
      begin
        # `el.text_content` reads the element's visible text content.
        # `&.strip` is Ruby's "safe navigation" operator: it calls `.strip`
        # (trim whitespace) ONLY if text_content isn't nil — if it IS nil,
        # the whole expression short-circuits to nil instead of raising a
        # NoMethodError trying to call .strip on nil.
        text = el.text_content&.strip
        # Skip elements with no real text, or absurdly long ones (likely a
        # big wrapper div containing the whole page's text rather than one
        # meaningful snippet) — `next` skips the rest of this iteration
        # and moves on to the next element in the loop.
        next if text.blank? || text.length > 200   # Skip empty or huge blocks

        # `.match?(pattern)` tests the text against the regex pattern
        # passed into this method (e.g. PRICE_PATTERNS) — true if it
        # matches anywhere in the text.
        if text.match?(pattern)
          results << {
            # `.truncate(100)` is a Rails String helper that shortens the
            # text to at most 100 characters, appending "..." if it had to
            # cut it short — keeps the report readable.
            text:     text.truncate(100),
            # `el.evaluate("el => el.tagName.toLowerCase()")` runs actual
            # JAVASCRIPT inside the browser page (Playwright lets Ruby code
            # execute JS snippets against a specific element) to read its
            # HTML tag name (like "div" or "span") in lowercase.
            tag:      el.evaluate("el => el.tagName.toLowerCase()"),
            selector: describe_element(el),
            id:       el.get_attribute("id"),
            classes:  el.get_attribute("class")
          }
        end
        # `end` closes the `if text.match?(pattern)` check above.
      rescue
        # Skip elements we can't read
        #
        # A bare `rescue` with no `=> e` and no error class still catches
        # any StandardError — it's used here purely to skip past a
        # problematic element without caring what specifically went wrong.
      end
      # `end` closes the `begin/rescue` block for this one element.
    end
    # `end` closes the `all_elements.each do |el|` loop above.

    results
  rescue => e
    # This `rescue` is attached to the METHOD itself (not a specific
    # inner block) — it would catch an error raised outside the per-element
    # begin/rescue above, such as query_selector_all itself failing.
    # Notably, on error this returns an ARRAY CONTAINING A STRING
    # describing the error, rather than the empty/results array the method
    # normally returns — callers treating this as a list of Hashes would
    # get a String in that position instead. Flagged separately below.
    [ "Error extracting elements: #{e.message}" ]
  end
  # `end` closes the `def extract_elements` method definition above.

  # Find container elements (repeating cards or list items)
  def find_containers(page, pattern, limit: 5)
    containers = []

    # Look for elements with multiple children that match the pattern
    #
    # A list of CSS selector strings to try, one at a time — each one is a
    # guess at what a "repeating card" container might look like on a
    # storage company site.
    candidate_selectors = [
      "[class*='result']", "[class*='card']", "[class*='item']",
      "[class*='location']", "[class*='facility']", "[class*='unit']",
      "li[class]", "article", ".row > div[class]"
    ]

    candidate_selectors.each do |selector|
      break if containers.length >= limit

      elements = page.query_selector_all(selector)
      # If nothing on the page matches this particular candidate selector,
      # move on to the next one — `next` skips the rest of the current
      # loop iteration without recording anything.
      next if elements.empty?

      # Check if any of these elements contain pattern-matching text
      #
      # Only inspect the FIRST matching element as a representative sample
      # (rather than every one) — if there are, say, 40 facility cards on
      # the page, we just need to look at one of them to judge the whole
      # group.
      sample = elements.first
      begin
        # `sample&.text_content || ""` — safe-navigation read of the
        # sample's text, falling back to an empty string if sample were
        # somehow nil (defensive, though `elements.empty?` was already
        # checked above so sample here shouldn't actually be nil).
        text = sample&.text_content || ""
        if text.match?(pattern)
          containers << {
            selector:       selector,
            count:          elements.length,
            sample_text:    text.strip.truncate(200),
            sample_classes: sample.get_attribute("class"),
            sample_id:      sample.get_attribute("id"),
            # Calls the private describe_children helper below to summarize
            # what kind of child elements this container holds.
            first_child_tags: describe_children(sample)
          }
        end
        # `end` closes the `if text.match?(pattern)` check above.
      rescue
        # Silently skip this candidate selector if inspecting its sample
        # element raised an error.
      end
      # `end` closes the `begin/rescue` block for this candidate selector.
    end
    # `end` closes the `candidate_selectors.each do |selector|` loop above.

    containers
  rescue => e
    # Same pattern/caveat as extract_elements above: on an unexpected
    # error at the method level, this returns an array containing an error
    # STRING rather than the array of Hashes callers otherwise expect.
    [ "Error finding containers: #{e.message}" ]
  end
  # `end` closes the `def find_containers` method definition above.

  # Extract links matching a pattern
  def extract_links(page, pattern, limit: 10)
    links = []
    # `a[href]` selects every `<a>` (anchor/link) tag that has an `href`
    # attribute at all (excluding any stray anchor tags with no link target).
    all_links = page.query_selector_all("a[href]")

    all_links.each do |link|
      break if links.length >= limit
      begin
        text = link.text_content&.strip
        href = link.get_attribute("href")
        # If a link has neither visible text nor an href, there's nothing
        # useful to record about it.
        next if text.blank? && href.blank?

        # `(text || "").match?(pattern)` — guards against `text` being nil
        # (safe-navigation wasn't used here, so this explicit `|| ""`
        # fallback prevents calling `.match?` on nil) — matches if EITHER
        # the visible link text or the href URL itself matches the
        # pattern (e.g. contains the word "reserve" or "book").
        if (text || "").match?(pattern) || (href || "").match?(pattern)
          links << {
            text:     text&.truncate(60),
            href:     href&.truncate(120),
            classes:  link.get_attribute("class")
          }
        end
      rescue
      end
      # `end` closes the `begin/rescue` block for this link.
    end
    # `end` closes the `all_links.each do |link|` loop above.

    links
  rescue => e
    [ "Error extracting links: #{e.message}" ]
  end
  # `end` closes the `def extract_links` method definition above.

  # Collect all CSS class names and how many times each appears
  def collect_css_classes(page)
    # `Hash.new(0)` creates a Hash with a DEFAULT VALUE of 0 — meaning
    # looking up any key that hasn't been explicitly set yet returns 0
    # instead of nil. This is a common Ruby idiom for building a frequency
    # counter, since it lets `class_counts[c] += 1` work correctly even
    # the very first time a given class name `c` is seen.
    class_counts = Hash.new(0)

    # `[class]` selects every element that has a `class` attribute at all,
    # regardless of what it's set to.
    all_elements = page.query_selector_all("[class]")
    all_elements.each do |el|
      begin
        # `.get_attribute("class")` reads the raw class attribute string
        # (e.g. "card featured highlighted"). `.to_s` guards against nil.
        # `.split` breaks it into an array of individual class name
        # strings, splitting on any whitespace by default.
        classes = el.get_attribute("class").to_s.split
        # For every individual class name found on this element, bump its
        # running count by 1 in the class_counts hash.
        classes.each { |c| class_counts[c] += 1 }
        # `{ |c| ... }` here is the same kind of block as `do |c| ... end`
        # — Ruby allows curly-brace blocks as a compact alternative syntax
        # for short, single-line blocks.
      rescue
      end
      # `end` closes the `begin/rescue` for this element.
    end
    # `end` closes the `all_elements.each do |el|` loop above.

    # Return top 50 most common classes
    #
    # `.sort_by { |_, count| -count }` sorts the hash's key/value pairs.
    # `|_, count|` destructures each pair into two block variables — the
    # underscore `_` is Ruby convention for "a variable I'm receiving but
    # intentionally not using" (here, the class name itself is ignored for
    # sorting purposes). Sorting by `-count` (negative count) achieves a
    # DESCENDING sort by count, since `sort_by` normally sorts ascending.
    # `.first(50)` keeps only the top 50 entries after sorting.
    # `.to_h` converts the resulting array of [key, value] pairs back into
    # a proper Hash.
    class_counts.sort_by { |_, count| -count }.first(50).to_h
  rescue => e
    # FIXED: this used to return `{ error: e.message }` on failure — a
    # Hash whose one key/value pair isn't a real class-name/count pair,
    # unlike every entry this method normally returns. A caller reading
    # `findings[:all_classes_with_counts]` as "class name => count" (its
    # normal shape) would have silently treated that fake "error" entry as
    # real data instead of noticing something went wrong. Returning an
    # empty Hash keeps the SAME type and shape as the success case (just
    # with no entries), so callers can't misread it as a real class/count
    # pair; the underlying message is still visible in `e.message` to
    # anyone debugging interactively.
    {}
  end
  # `end` closes the `def collect_css_classes` method definition above.

  # Collect all data-* attribute names used on the page
  def collect_data_attributes(page)
    # `page.evaluate(<<~JS ... JS)` runs the JavaScript code inside the
    # heredoc directly INSIDE THE BROWSER PAGE (not in Ruby) and returns
    # its result back to Ruby. This is different from `el.evaluate` seen
    # earlier, which ran JS scoped to one specific element — this one runs
    # against the whole page/document.
    attrs = page.evaluate(<<~JS
      () => {
        const attrs = new Set();
        document.querySelectorAll('*').forEach(el => {
          Array.from(el.attributes)
            .filter(a => a.name.startsWith('data-'))
            .forEach(a => attrs.add(a.name));
        });
        return Array.from(attrs).sort();
      }
    JS
    )
    # The JavaScript above: `() => { ... }` is a JS arrow function (this
    # whole thing IS the function passed to page.evaluate). It creates a
    # `Set` (a collection that automatically ignores duplicate values),
    # loops over every element on the page (`document.querySelectorAll('*')`
    # selects literally every element), and for each one, looks at all of
    # its HTML attributes, keeps only the ones whose name starts with
    # "data-" (custom data attributes commonly used by JS frameworks like
    # React/Vue to attach extra info to elements), and adds each such
    # attribute NAME (not value) to the Set. Finally it converts the Set
    # to a sorted Array and returns it — Playwright automatically converts
    # this JS array into a Ruby array for the `attrs` variable above.
    attrs
  rescue => e
    [ "Error collecting data attributes: #{e.message}" ]
  end
  # `end` closes the `def collect_data_attributes` method definition above.

  # Describe an element in a way that could be used as a CSS selector
  def describe_element(el)
    # `el.evaluate("el => el.tagName.toLowerCase()") rescue "?"` — this is
    # Ruby's "inline rescue" modifier: if the expression before `rescue`
    # raises any StandardError, the expression's value becomes whatever
    # follows `rescue` instead (here, the string "?") rather than the
    # error propagating up. Handy shorthand for "try this, and if it
    # blows up, just use this fallback value."
    tag     = el.evaluate("el => el.tagName.toLowerCase()") rescue "?"
    id      = el.get_attribute("id")
    # `.to_s.split.first(3).join(".")` — converts the class attribute to a
    # string (guarding nil), splits it into individual class names,
    # takes at most the first 3 of them, and joins those back together
    # separated by periods (mimicking CSS class-selector syntax like
    # `.foo.bar.baz`).
    classes = el.get_attribute("class").to_s.split.first(3).join(".")

    # Builds a CSS-selector-like description string piece by piece,
    # starting with just the tag name.
    selector = tag
    # `+=` appends to the string in place. Only add an `#id` part if there
    # actually is an id (`.present?` — not nil/blank).
    selector += "##{id}" if id.present?
    # Only add a `.class.names` part if there are any classes.
    selector += ".#{classes}" if classes.present?
    selector
  rescue
    # Catches any error from the whole method body (e.g. if `el` doesn't
    # respond the way expected) and falls back to a generic placeholder
    # string instead of crashing whatever called this.
    "unknown"
  end
  # `end` closes the `def describe_element` method definition above.

  # Describe the immediate children of an element
  def describe_children(el)
    # Runs JS scoped to this one element (`el` inside the JS arrow
    # function refers to the browser element, shadowing/unrelated to the
    # Ruby `el` parameter of the same name — they're in completely
    # separate languages).
    el.evaluate(<<~JS
      el => {
        return Array.from(el.children)
          .slice(0, 5)
          .map(c => c.tagName.toLowerCase() + (c.className ? '.' + c.className.split(' ')[0] : ''));
      }
    JS
    )
    # The JS: `el.children` is the element's direct child elements (not
    # grandchildren, not text nodes). `Array.from(...)` converts that
    # browser-native collection into a real JS array so array methods work
    # on it. `.slice(0, 5)` keeps just the first 5 children. `.map(...)`
    # transforms each child into a short descriptive string: its tag name
    # in lowercase, plus (if it has any CSS class) a period followed by
    # just its FIRST class name — mirroring simplified CSS selector
    # notation, e.g. "div.card".
  rescue
    # If anything goes wrong (e.g. el has no children property somehow),
    # fall back to an empty array rather than raising.
    []
  end
  # `end` closes the `def describe_children` method definition above.

  # Build a human-readable report from the findings hash
  def build_report(findings)
    lines = []
    lines << "RECON REPORT: #{findings[:company]}"
    lines << "Generated: #{findings[:timestamp]}"
    lines << "URL: #{findings[:url]}"
    lines << "Page Title: #{findings[:page_title]}"
    lines << ""

    lines << "--- PRICE ELEMENTS (#{findings[:price_elements].length} found) ---"
    # Loops over each price element hash found earlier and appends a few
    # descriptive lines about it to the report, followed by a blank line
    # separator.
    findings[:price_elements].each do |el|
      lines << "  Text: #{el[:text]}"
      lines << "  Selector: #{el[:selector]}"
      lines << "  Classes: #{el[:classes]}"
      lines << ""
    end
    # `end` closes the `findings[:price_elements].each do |el|` loop above.

    lines << "--- SIZE ELEMENTS (#{findings[:size_elements].length} found) ---"
    findings[:size_elements].each do |el|
      lines << "  Text: #{el[:text]}"
      lines << "  Selector: #{el[:selector]}"
      lines << ""
    end
    # `end` closes this `.each do |el|` loop.

    lines << "--- FACILITY CONTAINERS ---"
    findings[:facility_containers].each do |c|
      lines << "  Selector: #{c[:selector]} (#{c[:count]} elements found)"
      lines << "  Sample text: #{c[:sample_text]}"
      lines << "  Classes: #{c[:sample_classes]}"
      lines << ""
    end
    # `end` closes this `.each do |c|` loop.

    lines << "--- UNIT CONTAINERS ---"
    findings[:unit_containers].each do |c|
      lines << "  Selector: #{c[:selector]} (#{c[:count]} elements found)"
      lines << "  Sample text: #{c[:sample_text]}"
      lines << ""
    end
    # `end` closes this `.each do |c|` loop.

    lines << "--- BOOKING LINKS ---"
    findings[:booking_links].each do |link|
      lines << "  Text: #{link[:text]}"
      lines << "  Href: #{link[:href]}"
      lines << ""
    end
    # `end` closes this `.each do |link|` loop.

    lines << "--- TOP CSS CLASSES ---"
    # `.each do |cls, count| ... end` — iterating over a Hash yields each
    # key/value pair, destructured here into `cls` (the class name) and
    # `count` (how many times it appeared).
    findings[:all_classes_with_counts].each do |cls, count|
      lines << "  .#{cls} (#{count}x)"
    end
    # `end` closes this `.each do |cls, count|` loop.

    lines << ""
    lines << "--- DATA ATTRIBUTES ---"
    # `.join(", ")` combines the array of data-* attribute name strings
    # into one comma-separated line.
    lines << findings[:data_attributes].join(", ")

    lines << ""
    lines << "--- PAGINATION ---"
    if findings[:pagination][:exists]
      lines << "  Pagination found: #{findings[:pagination][:selector]}"
    else
      lines << "  No pagination detected"
    end
    # `end` closes the `if findings[:pagination][:exists]` block above.

    lines.join("\n")
  end
  # `end` closes the `def build_report` method definition above.

  # Extract a usable company name from the URL
  def extract_company_name(url)
    # `URI.parse(url).host` parses the URL string into its component parts
    # and reads just the host/domain portion (e.g.
    # "www.cubesmart.com" from "https://www.cubesmart.com/storage-units/").
    # `rescue ""` (inline rescue modifier, same as seen in describe_element
    # above) falls back to an empty string if the URL is malformed and
    # can't be parsed at all.
    host = URI.parse(url).host rescue ""
    # `.sub(/^www\./, "")` uses a regex to remove a leading "www." if
    # present (`^` anchors the match to the start of the string; `\.` is
    # an escaped/literal period, since a plain `.` in regex normally means
    # "any character"). `.split(".").first` then splits the remaining
    # host on periods and takes just the first segment (e.g.
    # "cubesmart" from "cubesmart.com"). `.to_s` guards against nil (if
    # host itself was nil/blank). `.presence` (Rails helper) turns an
    # empty string back into nil so the `||` fallback below can catch it.
    host.sub(/^www\./, "").split(".").first.to_s.presence || "unknown"
  rescue
    # Catches literally anything unexpected in this whole method and
    # falls back to a safe generic default company name.
    "unknown"
  end
  # `end` closes the `def extract_company_name` method definition above.
end
# `end` closes the `class ReconService` definition that started at the top
# of this file.
