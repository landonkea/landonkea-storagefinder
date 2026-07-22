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

class ReconService
  # Patterns we use to find "interesting" elements on the page
  # These are guesses that work on most storage websites
  PRICE_PATTERNS     = /\$\d|\bprice\b|\brate\b|\bmonth\b|\bmo\b/i
  SIZE_PATTERNS      = /\d+[x×]\d+|\bsize\b|\bdimension\b|\bwidth\b|\bdepth\b/i
  ADDRESS_PATTERNS   = /\baddress\b|\bstreet\b|\bcity\b|\bstate\b|\bzip\b|\bphone\b/i
  FACILITY_PATTERNS  = /\bfacility\b|\blocation\b|\bstore\b|\bstorage\b|\bresult\b/i
  UNIT_PATTERNS      = /\bunit\b|\bspace\b|\broom\b|\bstorage.unit\b/i
  LINK_PATTERNS      = /\breserve\b|\brent\b|\bbook\b|\bdetail\b|\bview\b/i

  # ---------------------------------------------------------------------------
  # CLASS METHOD — the main entry point
  # ---------------------------------------------------------------------------
  def self.run(url, company_name: nil)
    new(url, company_name: company_name).run
  end

  # ---------------------------------------------------------------------------
  # INITIALIZER
  # ---------------------------------------------------------------------------
  def initialize(url, company_name: nil)
    @url          = url
    @company_name = company_name || extract_company_name(url)
    @timestamp    = Time.current.strftime("%Y%m%d_%H%M%S")
    @output_dir   = Rails.root.join("recon")

    # Create output directory if it doesn't exist
    FileUtils.mkdir_p(@output_dir)

    # Base name for all output files
    @base_filename = "#{@output_dir}/#{@company_name.downcase.gsub(/\W+/, "_")}_#{@timestamp}"
  end

  # ---------------------------------------------------------------------------
  # RUN
  # ---------------------------------------------------------------------------
  def run
    puts ""
    puts "=" * 70
    puts "STORAGEFINDER RECON TOOL"
    puts "=" * 70
    puts "URL:     #{@url}"
    puts "Company: #{@company_name}"
    puts "Output:  #{@output_dir}"
    puts ""
    puts "Launching browser..."

    playwright_path = `timeout 10 which playwright 2>/dev/null`.strip
    playwright_path = "playwright" if playwright_path.blank?  # fallback, let it fail with a clear error

    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      browser = playwright.chromium.launch(
        headless: false,  # Visible so you can see what the recon tool is doing
        args: [ "--window-size=1280,900" ]
      )

      page = browser.new_page
      page.set_viewport_size(width: 1280, height: 900)

      # Set a realistic User-Agent
      page.set_extra_http_headers({
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      })

      begin
        puts "Loading page..."
        page.goto(@url, waitUntil: "domcontentloaded", timeout: 30_000)

        # Wait a bit for lazy-loaded content to appear
        page.wait_for_timeout(3000)
        puts "Page loaded."

        # -----------------------------------------------------------------------
        # 1. Screenshot
        # -----------------------------------------------------------------------
        screenshot_path = "#{@base_filename}_screenshot.png"
        page.screenshot(path: screenshot_path, fullPage: true)
        puts "✓ Screenshot saved: #{screenshot_path}"

        # -----------------------------------------------------------------------
        # 2. Extract all interesting elements and their selectors
        # -----------------------------------------------------------------------
        puts "Scanning page structure..."
        findings = scan_page(page)

        # -----------------------------------------------------------------------
        # 3. Write JSON data file
        # -----------------------------------------------------------------------
        json_path = "#{@base_filename}_data.json"
        File.write(json_path, JSON.pretty_generate(findings))
        puts "✓ JSON data saved: #{json_path}"

        # -----------------------------------------------------------------------
        # 4. Write human-readable report
        # -----------------------------------------------------------------------
        report = build_report(findings)
        report_path = "#{@base_filename}_report.txt"
        File.write(report_path, report)
        puts "✓ Report saved: #{report_path}"

        # Print a quick summary to the console
        puts ""
        puts "=" * 70
        puts "RECON SUMMARY FOR #{@company_name.upcase}"
        puts "=" * 70
        puts report
        puts ""
        puts "Share the recon/ folder contents with Claude to get a real parser written."

      rescue Playwright::TimeoutError => e
        puts "ERROR: Page timed out loading #{@url}"
        puts "Details: #{e.message}"
        puts "Try opening the URL manually in a browser to check if it's accessible."

      rescue => e
        puts "ERROR: #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n")

      ensure
        browser.close
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  # Scan the page for elements that look relevant to storage unit data
  def scan_page(page)
    findings = {
      url:           @url,
      company:       @company_name,
      timestamp:     @timestamp,
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
    pagination_el = page.query_selector(
      ".pagination, [aria-label='pagination'], .pager, nav[role='navigation'], .load-more"
    )
    findings[:pagination] = pagination_el ? {
      exists:   true,
      selector: describe_element(pagination_el)
    } : { exists: false }

    findings
  end

  # Extract elements whose text matches a pattern
  def extract_elements(page, pattern, limit: 20)
    results = []

    # Get all text-containing elements
    all_elements = page.query_selector_all("p, span, div, td, li, h1, h2, h3, h4, label, [class*='price'], [class*='size'], [class*='rate']")

    all_elements.each do |el|
      break if results.length >= limit

      begin
        text = el.text_content&.strip
        next if text.blank? || text.length > 200   # Skip empty or huge blocks

        if text.match?(pattern)
          results << {
            text:     text.truncate(100),
            tag:      el.evaluate("el => el.tagName.toLowerCase()"),
            selector: describe_element(el),
            id:       el.get_attribute("id"),
            classes:  el.get_attribute("class")
          }
        end
      rescue
        # Skip elements we can't read
      end
    end

    results
  rescue => e
    [ "Error extracting elements: #{e.message}" ]
  end

  # Find container elements (repeating cards or list items)
  def find_containers(page, pattern, limit: 5)
    containers = []

    # Look for elements with multiple children that match the pattern
    candidate_selectors = [
      "[class*='result']", "[class*='card']", "[class*='item']",
      "[class*='location']", "[class*='facility']", "[class*='unit']",
      "li[class]", "article", ".row > div[class]"
    ]

    candidate_selectors.each do |selector|
      break if containers.length >= limit

      elements = page.query_selector_all(selector)
      next if elements.empty?

      # Check if any of these elements contain pattern-matching text
      sample = elements.first
      begin
        text = sample&.text_content || ""
        if text.match?(pattern)
          containers << {
            selector:       selector,
            count:          elements.length,
            sample_text:    text.strip.truncate(200),
            sample_classes: sample.get_attribute("class"),
            sample_id:      sample.get_attribute("id"),
            first_child_tags: describe_children(sample)
          }
        end
      rescue
      end
    end

    containers
  rescue => e
    [ "Error finding containers: #{e.message}" ]
  end

  # Extract links matching a pattern
  def extract_links(page, pattern, limit: 10)
    links = []
    all_links = page.query_selector_all("a[href]")

    all_links.each do |link|
      break if links.length >= limit
      begin
        text = link.text_content&.strip
        href = link.get_attribute("href")
        next if text.blank? && href.blank?

        if (text || "").match?(pattern) || (href || "").match?(pattern)
          links << {
            text:     text&.truncate(60),
            href:     href&.truncate(120),
            classes:  link.get_attribute("class")
          }
        end
      rescue
      end
    end

    links
  rescue => e
    [ "Error extracting links: #{e.message}" ]
  end

  # Collect all CSS class names and how many times each appears
  def collect_css_classes(page)
    class_counts = Hash.new(0)

    all_elements = page.query_selector_all("[class]")
    all_elements.each do |el|
      begin
        classes = el.get_attribute("class").to_s.split
        classes.each { |c| class_counts[c] += 1 }
      rescue
      end
    end

    # Return top 50 most common classes
    class_counts.sort_by { |_, count| -count }.first(50).to_h
  rescue => e
    { error: e.message }
  end

  # Collect all data-* attribute names used on the page
  def collect_data_attributes(page)
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
    attrs
  rescue => e
    [ "Error collecting data attributes: #{e.message}" ]
  end

  # Describe an element in a way that could be used as a CSS selector
  def describe_element(el)
    tag     = el.evaluate("el => el.tagName.toLowerCase()") rescue "?"
    id      = el.get_attribute("id")
    classes = el.get_attribute("class").to_s.split.first(3).join(".")

    selector = tag
    selector += "##{id}" if id.present?
    selector += ".#{classes}" if classes.present?
    selector
  rescue
    "unknown"
  end

  # Describe the immediate children of an element
  def describe_children(el)
    el.evaluate(<<~JS
      el => {
        return Array.from(el.children)
          .slice(0, 5)
          .map(c => c.tagName.toLowerCase() + (c.className ? '.' + c.className.split(' ')[0] : ''));
      }
    JS
    )
  rescue
    []
  end

  # Build a human-readable report from the findings hash
  def build_report(findings)
    lines = []
    lines << "RECON REPORT: #{findings[:company]}"
    lines << "Generated: #{findings[:timestamp]}"
    lines << "URL: #{findings[:url]}"
    lines << "Page Title: #{findings[:page_title]}"
    lines << ""

    lines << "--- PRICE ELEMENTS (#{findings[:price_elements].length} found) ---"
    findings[:price_elements].each do |el|
      lines << "  Text: #{el[:text]}"
      lines << "  Selector: #{el[:selector]}"
      lines << "  Classes: #{el[:classes]}"
      lines << ""
    end

    lines << "--- SIZE ELEMENTS (#{findings[:size_elements].length} found) ---"
    findings[:size_elements].each do |el|
      lines << "  Text: #{el[:text]}"
      lines << "  Selector: #{el[:selector]}"
      lines << ""
    end

    lines << "--- FACILITY CONTAINERS ---"
    findings[:facility_containers].each do |c|
      lines << "  Selector: #{c[:selector]} (#{c[:count]} elements found)"
      lines << "  Sample text: #{c[:sample_text]}"
      lines << "  Classes: #{c[:sample_classes]}"
      lines << ""
    end

    lines << "--- UNIT CONTAINERS ---"
    findings[:unit_containers].each do |c|
      lines << "  Selector: #{c[:selector]} (#{c[:count]} elements found)"
      lines << "  Sample text: #{c[:sample_text]}"
      lines << ""
    end

    lines << "--- BOOKING LINKS ---"
    findings[:booking_links].each do |link|
      lines << "  Text: #{link[:text]}"
      lines << "  Href: #{link[:href]}"
      lines << ""
    end

    lines << "--- TOP CSS CLASSES ---"
    findings[:all_classes_with_counts].each do |cls, count|
      lines << "  .#{cls} (#{count}x)"
    end

    lines << ""
    lines << "--- DATA ATTRIBUTES ---"
    lines << findings[:data_attributes].join(", ")

    lines << ""
    lines << "--- PAGINATION ---"
    if findings[:pagination][:exists]
      lines << "  Pagination found: #{findings[:pagination][:selector]}"
    else
      lines << "  No pagination detected"
    end

    lines.join("\n")
  end

  # Extract a usable company name from the URL
  def extract_company_name(url)
    host = URI.parse(url).host rescue ""
    host.sub(/^www\./, "").split(".").first.to_s.presence || "unknown"
  rescue
    "unknown"
  end
end
