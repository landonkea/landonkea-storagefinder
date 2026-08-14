# =============================================================================
# UNIT MODEL
# =============================================================================
# A Unit represents one type of storage unit at a specific facility.
# Example: "10x20 Climate Controlled, $89/mo" at "Extra Space - Gilbert East"
#
# Every unit belongs to:
#   - A Facility (which building is it at?)
#   - A CrawlRun (which crawl session found/updated this record?)
# =============================================================================

# `class Unit < ApplicationRecord` defines a Ruby class named Unit that
# inherits from ApplicationRecord (see app/models/application_record.rb).
# Inheriting from ApplicationRecord, which itself inherits from
# `ActiveRecord::Base`, makes this an "ActiveRecord model": a Ruby class
# that represents one row of a database table (here, the "units" table,
# inferred automatically from the class name). Because of that, every
# column in the table (size, monthly_price, available, ...) is
# automatically readable and writable as if it were a plain Ruby method,
# e.g. `some_unit.monthly_price`, with no extra code required.
class Unit < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  # `belongs_to` declares that this table has a foreign key column (e.g.
  # `facility_id`) pointing at exactly one row in another table. It
  # generates a method (e.g. `unit.facility`) that looks up and returns
  # that related record. By default in Rails, `belongs_to` also implicitly
  # requires the association to be present, a Unit can't be saved without
  # a facility_id/crawl_run_id already set.
  belongs_to :facility   # Every unit must belong to a facility
  belongs_to :crawl_run  # Every unit must be associated with the crawl that found it

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # `validates` declares a rule a record must satisfy before Rails will save
  # it to the database. If a validation fails, Rails refuses to save and
  # instead records a human-readable error message (accessible via
  # `record.errors`) that can be shown back to the user.

  # Requires `size` to be present (not nil, not an empty string).
  validates :size,         presence: { message: "Unit size is required (e.g. 10x10)" }
  # Requires `collected_at` (the timestamp this unit's data was scraped) to
  # be present.
  validates :collected_at, presence: { message: "Collection timestamp is required" }

  # Size must match a pattern like "10x10", "10x20", "12x30", etc.
  # `format:` checks the value against a regular expression, a pattern for
  # matching text. `/\A\d+x\d+\z/i` reads as: `\A` = start of string,
  # `\d+` = one or more digits, a literal `x`, `\d+` = one or more digits
  # again, `\z` = end of string. The `i` flag after the closing `/` makes
  # it case-insensitive, so an uppercase "10X10" would also match.
  # `allow_blank: true` skips this check when size is blank (already
  # covered by the presence validation above).
  validates :size, format: {
    with:    /\A\d+x\d+\z/i,
    message: "Size must be in WIDTHxDEPTH format (e.g. 10x10, 10x20)"
  }, allow_blank: true

  # Price must be positive if provided
  # `numericality:` requires the value to be a number satisfying the given
  # constraint (here, `greater_than: 0`). `allow_nil: true` means this rule
  # is skipped entirely when monthly_price is nil (e.g. a scraper couldn't
  # find a price), nil prices are allowed, but a price of 0 or less is not.
  validates :monthly_price, numericality: {
    greater_than: 0,
    message:      "Monthly price must be greater than $0"
  }, allow_nil: true

  # ---------------------------------------------------------------------------
  # CALLBACKS
  # ---------------------------------------------------------------------------
  # Callbacks are methods that run automatically at certain points in an
  # object's lifecycle (before save, after create, etc.)
  # ---------------------------------------------------------------------------

  # Before saving, parse the size string into width/depth/sqft
  # This way we can filter by "at least 10x10" without string parsing later
  #
  # `before_save` is a Rails "callback" declaration: it registers the
  # `parse_dimensions` method (defined near the bottom of this file, in the
  # PRIVATE METHODS section) to run automatically every time a Unit record
  # is about to be saved (whether it's a brand-new record or an update to
  # an existing one), immediately before the actual database write happens.
  before_save :parse_dimensions

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  # A "scope" is Rails' way of defining a named, reusable database query
  # exposed as a class-level method, e.g. `Unit.available`. Each one below
  # is written as a lambda, `-> { ... }` (no arguments) or `->(arg) { ... }`
  # (with arguments), an anonymous, reusable chunk of code that Rails calls
  # when the scope's name is invoked.

  # Only units that are currently available for rent
  scope :available,          -> { where(available: true) }

  # Only climate-controlled units
  scope :climate_controlled, -> { where(climate_controlled: true) }

  # Exclude unit types we don't care about (parking, RV, boat, etc.)
  scope :enclosed,           -> { where(indoor: true, drive_up: false) }

  # Filter by minimum size
  # Usage: Unit.at_least_size(10, 10), returns all units 10x10 or larger
  #
  # `->(min_width, min_depth) { ... }` is a lambda taking two positional
  # arguments. `where("width_ft >= ? AND depth_ft >= ?", min_width,
  # min_depth)` builds a SQL condition with two `?` placeholders, filled in
  # order by the two arguments that follow, Rails substitutes them safely,
  # avoiding SQL injection (as opposed to directly interpolating the values
  # into the string).
  scope :at_least_size, ->(min_width, min_depth) {
    where("width_ft >= ? AND depth_ft >= ?", min_width, min_depth)
  }

  # Filter to specific sizes (array of size strings)
  # Usage: Unit.with_sizes(["10x10", "10x20"])
  #
  # `where(size: sizes) if sizes.present?`, the `if` here is the inline
  # modifier form: the `where(...)` call only runs when `sizes` is present
  # (not nil/empty). If `sizes` is blank, this lambda's body evaluates the
  # `if` as false and the whole expression returns nil, meaning this scope
  # effectively "does nothing" (returns nil, not a query) when given no
  # sizes, worth noting since chaining further scope calls onto nil would
  # raise an error rather than silently no-op.
  scope :with_sizes, ->(sizes) {
    where(size: sizes) if sizes.present?
  }

  # Exclude specific unit types
  # `where.not(unit_type: types)` builds a SQL "NOT IN" style condition,
  # excluding any unit whose `unit_type` appears in the `types` array.
  # Same "returns nil when types is blank" caveat as with_sizes above.
  scope :exclude_types, ->(types) {
    where.not(unit_type: types) if types.present?
  }

  # Sort by cheapest price first
  # `order(monthly_price: :asc)` sorts ascending (smallest/cheapest number
  # first) by the monthly_price column. `:asc` is a Ruby symbol (a
  # lightweight, immutable label, written with a leading `:`) used here as
  # a named option value rather than a string.
  scope :cheapest_first,   -> { order(monthly_price: :asc) }

  # Sort by largest unit first (by square footage)
  # `:desc` sorts descending (largest number first).
  scope :largest_first,    -> { order(sqft: :desc) }

  # Only units collected in the most recent crawl run
  scope :from_latest_crawl, -> {
    # `CrawlRun.completed` calls the `completed` scope defined in
    # app/models/crawl_run.rb (all crawl runs with status "completed"),
    # then sorts newest-first by `completed_at` and takes just the single
    # most recent one via `.first` (which is nil if no crawl has completed).
    latest_run = CrawlRun.completed.order(completed_at: :desc).first
    # `return none unless latest_run` exits this lambda's block early,
    # returning `none` (a Rails method that returns an empty, chainable
    # query, like an empty array, but still safely usable with further
    # scope chaining, unlike a bare nil) when there's no completed crawl.
    return none unless latest_run  # Return empty if no crawl has been run
    # Otherwise, filters units down to only those belonging to that one
    # latest crawl run.
    where(crawl_run: latest_run)
  }

  # Units from the last N days (for history/trend queries)
  # Note: despite the comment above, this scope actually takes a specific
  # DATE/time value to filter from (`since`), not a number of days, see
  # the "flag but don't fix" notes for more on this.
  scope :since,            ->(date) { where("collected_at >= ?", date) }

  # ---------------------------------------------------------------------------
  # UNIT TYPE CONSTANTS
  # ---------------------------------------------------------------------------
  # These are the unit types we actively EXCLUDE from results by default.
  # Parser modules should tag units with these types so filters work correctly.
  # ---------------------------------------------------------------------------
  # `EXCLUDED_TYPES = ...` defines a Ruby CONSTANT, a variable whose name
  # starts with a capital letter, which by convention is meant to never be
  # reassigned after this point. `%w[...]` is shorthand for an array of
  # strings, one per space-separated word. `.freeze` locks the array so it
  # can't be mutated in place later (e.g. nobody can accidentally call
  # `EXCLUDED_TYPES << "boat"` somewhere else in the app and silently change
  # this shared list), a common safety practice for shared constants.
  EXCLUDED_TYPES = %w[
    parking
    rv
    boat
    locker
    mailbox
    vehicle
    motorcycle
    outdoor
  ].freeze

  # Unit sizes we specifically care about (the defaults)
  DEFAULT_SIZES = %w[10x10 10x15 10x20 10x25 10x30].freeze

  # Minimum acceptable size in feet (anything smaller gets filtered)
  # Plain integer constants (no array/freeze needed since integers are
  # already immutable values in Ruby).
  MIN_WIDTH_FT = 10
  MIN_DEPTH_FT = 10

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------
  # Everything below (until CLASS METHODS) is a regular Ruby instance
  # method, callable on one particular Unit record, e.g.
  # `some_unit.best_price`.

  # Returns the display price, use web special if it's lower than regular price
  # This is what gets shown on the dashboard as the "best price"
  #
  # Returns the price to actually show/compare for this unit. Self-storage
  # sites often list a "web special" (a lower promo price) alongside the
  # regular monthly price, we want whichever one is actually cheaper.
  #
  # `def` starts a method definition; `best_price` is its name; there are no
  # parentheses because this method takes no arguments (Ruby allows omitting
  # them). The method body runs top to bottom and returns whatever its LAST
  # expression evaluates to, Ruby methods don't need an explicit `return`.
  def best_price
    # Safely handle nil monthly_price, return web_special if it exists, else monthly
    #
    # `.present?` is a Rails helper meaning "not nil and not empty", it's
    # true for any real price, false if web_special_price was never set.
    # `&&` is "and": both sides must be true for the whole condition to be true.
    # The condition inside the outer parentheses is itself an "or" (`||`):
    # either monthly_price is nil (nothing to compare against), OR the web
    # special is strictly less than the monthly price (`.to_d` converts
    # monthly_price to a BigDecimal so the `<` comparison is precise with
    # money, avoiding floating-point rounding errors).
    if web_special_price.present? && (monthly_price.nil? || web_special_price < monthly_price.to_d)
      # If we got here, the web special is the better price, return it.
      # This is the method's return value because it's the last thing
      # evaluated on this branch.
      web_special_price
    else
      # Otherwise (no web special, or it's not actually cheaper), fall back
      # to the regular monthly price. `monthly_price` may itself be nil here
      # (e.g. a scraper failed to find a price), that's handled by callers.
      monthly_price
    end
    # `end` closes the `if/else` block that started above.
  end
  # `end` closes the `def best_price` method definition that started above.

  # Returns true if this unit has a web special that's lower than the regular price
  def has_web_special?
    # Unlike best_price above, this comparison does NOT guard against
    # monthly_price being nil before calling `.to_d` on it, see the "flag
    # but don't fix" notes for why that matters.
    web_special_price.present? && web_special_price < monthly_price.to_d
  end
  # `end` closes the `def has_web_special?` method definition.

  # Returns a formatted price string like "$89.00" or "Not listed"
  def formatted_price
    return "Not listed" if monthly_price.nil?
    # `"%.2f" % monthly_price` uses Ruby's `%` string-formatting operator
    # (similar to C's printf): `%.2f` means "format as a floating-point
    # number with exactly 2 digits after the decimal point", standard for
    # displaying money. The result is spliced into the surrounding string
    # via `#{...}` interpolation.
    "$#{"%.2f" % monthly_price}"
  end
  # `end` closes the `def formatted_price` method definition.

  # Returns a formatted web special price like "$79.00" or nil
  def formatted_web_special
    # `return nil unless has_web_special?` is the inline modifier form of
    # `unless` (opposite of `if`), exits early with nil when there's no
    # (cheaper) web special to show, calling the has_web_special? method
    # defined just above.
    return nil unless has_web_special?
    "$#{"%.2f" % web_special_price}"
  end
  # `end` closes the `def formatted_web_special` method definition.

  # Returns a CSS color class for the price (green/yellow/red)
  # Used in the dashboard table to color-code cells
  #
  # The two breakpoints below used to be hardcoded ($100/$150), they're
  # now Setting rows (see db/seeds.rb's "display_price_green_max"/
  # "display_price_yellow_max", category "display"), configurable from the
  # Settings page like every other tunable value in this app, rather than
  # requiring a code change to move the line between "that's a good price"
  # and "that's expensive."
  def price_color_class
    return "price-unknown" if best_price.nil?

    # `Setting.get(key, default: ...)` reads the current configured
    # breakpoint, falling back to the original hardcoded values if the
    # setting row is somehow missing (e.g. an older database that hasn't
    # run the latest db/seeds.rb yet), see Setting.get in
    # app/models/setting.rb, which also casts the stored string back to a
    # number via each row's `input_type`.
    green_max  = Setting.get("display_price_green_max",  default: 99)
    yellow_max = Setting.get("display_price_yellow_max", default: 149)

    # `case best_price when ... end` is Ruby's multi-branch conditional.
    # Unlike the `case`/`when` examples elsewhere in this codebase that
    # compare against exact values, the `when` clauses here use RANGES:
    # `..green_max` is a "beginless range" meaning "everything up to and
    # including green_max" (no explicit starting value), and
    # `green_max..yellow_max` is an ordinary range built from the two
    # configured breakpoints. Ruby's `case` checks each range with `===`,
    # which for a Range means "does this range include the value being
    # tested."
    case best_price
    when ..green_max          then "price-green"
    when green_max..yellow_max then "price-yellow"
    else                            "price-red"
    end
    # `end` closes the `case best_price` block above; its result (whichever
    # string matched) is this method's return value.
  end
  # `end` closes the `def price_color_class` method definition.

  # Returns the square footage as a formatted string like "200 sq ft"
  def sqft_label
    return "Unknown" if sqft.nil?
    "#{sqft} sq ft"
  end
  # `end` closes the `def sqft_label` method definition.

  # Returns true if this unit meets the standard filter criteria
  def matches_default_filters?
    # A single boolean expression spanning multiple lines, joined by `&&`
    # ("and") at the end of each line, every condition must be true for
    # the whole expression (and thus the method) to return true.
    # `climate_controlled` and `indoor` are boolean database columns read
    # directly as attributes. `!drive_up` negates the drive_up column
    # (true becomes false and vice versa), this unit must NOT be a
    # drive-up unit. `EXCLUDED_TYPES.exclude?(unit_type.to_s.downcase)`,
    # `.exclude?` is the opposite of `.include?`, true when the array does
    # NOT contain the given value; `unit_type.to_s.downcase` normalizes the
    # unit_type value to a lowercase string before checking it against the
    # EXCLUDED_TYPES constant defined earlier in this file. `width_ft.to_i
    # >= MIN_WIDTH_FT` and `depth_ft.to_i >= MIN_DEPTH_FT` require both
    # dimensions to meet the minimum size constants (also defined above).
    climate_controlled &&
      indoor &&
      !drive_up &&
      EXCLUDED_TYPES.exclude?(unit_type.to_s.downcase) &&
      width_ft.to_i >= MIN_WIDTH_FT &&
      depth_ft.to_i >= MIN_DEPTH_FT
  end
  # `end` closes the `def matches_default_filters?` method definition.

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------
  # `def self.method_name` defines a CLASS method, called directly on the
  # class itself, e.g. `Unit.apply_filters(...)`, rather than on one
  # particular Unit record.

  # Apply all active filters from a hash of filter options
  # This is called by the dashboard controller when the user sets filters
  #
  # filter_options example:
  #   {
  #     climate_controlled: true,
  #     sizes: ["10x10", "10x20"],
  #     exclude_types: ["parking", "rv"],
  #     min_width: 10,
  #     min_depth: 10,
  #     available_only: true
  #   }
  #
  # `filter_options = {}` is a positional argument defaulting to an empty
  # Ruby Hash (key-value map) when the caller passes nothing.
  def self.apply_filters(filter_options = {})
    scope = all  # Start with all units, then chain filters
    # `all` is a Rails method returning a query matching every Unit row;
    # `scope` is then progressively narrowed (reassigned) by each `if`
    # block below, building up the final filtered query step by step.

    # Filter by climate control
    # `filter_options[:climate_controlled]` reads the value stored under
    # the `:climate_controlled` symbol key in the hash (Hash lookup uses
    # square brackets, similar to array indexing but with a key instead of
    # a numeric position).
    if filter_options[:climate_controlled].present?
      scope = scope.where(climate_controlled: filter_options[:climate_controlled])
    end
    # `end` closes the `if filter_options[:climate_controlled].present?`
    # block above.

    # Filter by specific sizes
    if filter_options[:sizes].present?
      scope = scope.where(size: filter_options[:sizes])
    end
    # `end` closes the `if filter_options[:sizes].present?` block above.

    # Filter by minimum size
    # Both min_width AND min_depth must be present for this filter to
    # apply, `&&` requires both `.present?` checks to be true.
    if filter_options[:min_width].present? && filter_options[:min_depth].present?
      scope = scope.where(
        "width_ft >= ? AND depth_ft >= ?",
        filter_options[:min_width].to_i,
        filter_options[:min_depth].to_i
      )
    end
    # `end` closes the `if filter_options[:min_width].present? && ...`
    # block above.

    # Exclude specific unit types
    if filter_options[:exclude_types].present?
      scope = scope.where.not(unit_type: filter_options[:exclude_types])
    end
    # `end` closes the `if filter_options[:exclude_types].present?` block
    # above.

    # Exclude drive-up/outdoor units by default
    # `unless filter_options[:include_drive_up]` runs the block only when
    # that key is falsy (nil, false, or simply absent from the hash), so
    # by default (when the caller doesn't explicitly ask to include
    # drive-up units), this filter is applied automatically.
    unless filter_options[:include_drive_up]
      scope = scope.where(drive_up: false)
    end
    # `end` closes the `unless filter_options[:include_drive_up]` block
    # above.

    # Only available units by default
    unless filter_options[:include_unavailable]
      scope = scope.where(available: true)
    end
    # `end` closes the `unless filter_options[:include_unavailable]` block
    # above.

    # Only indoor units by default
    unless filter_options[:include_outdoor]
      scope = scope.where(indoor: true)
    end
    # `end` closes the `unless filter_options[:include_outdoor]` block
    # above.

    # The final, fully-filtered query, this is the method's return value
    # since it's the last expression evaluated.
    scope
  end
  # `end` closes the `def self.apply_filters` method definition.

  # Returns all unique sizes present in the database, sorted logically
  # Used to populate the size filter checkboxes
  def self.all_sizes
    # `pluck(:size)` runs an efficient SQL query fetching only the `size`
    # column (not whole Unit objects) as a plain Ruby array of strings.
    # `.uniq` removes duplicate entries. `.sort_by { |s| ... }` sorts the
    # array using the block's return value as the sort key for each
    # element `s`, rather than sorting the strings alphabetically (which
    # would incorrectly put "10x20" before "10x5", say, since it's
    # comparing characters, not numbers).
    pluck(:size).uniq.sort_by do |s|
      # Sort by total square footage (width * depth) so 10x10 comes before 10x20
      # `s.to_s.split("x")` splits a size string like "10x20" on the
      # literal character "x", producing an array of string pieces (e.g.
      # ["10", "20"]). `.map(&:to_i)` converts EVERY element of that array
      # to an integer, `&:to_i` is shorthand for `{ |piece| piece.to_i }`,
      # turning the `:to_i` method into a block via the `&` "to proc"
      # operator.
      parts = s.to_s.split("x").map(&:to_i)
      # Computes width * depth (total square footage) as the sort key.
      # `rescue 0` here is Ruby's inline rescue modifier: if the
      # multiplication raises an error for any reason (e.g. `parts` didn't
      # have exactly 2 usable numbers), the whole expression falls back to
      # 0 instead of crashing the sort.
      parts[0].to_i * parts[1].to_i rescue 0
    end
    # `end` closes the `do |s| ... end` block passed to `sort_by`; its
    # overall result (the sorted array) is this method's return value.
  end
  # `end` closes the `def self.all_sizes` method definition.

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  # `private` marks everything below it as callable only from inside this
  # class itself (e.g. automatically by the before_save callback), not from
  # outside code like controllers, hiding implementation details that
  # aren't meant to be part of this model's public interface.
  private

  # Parse the size string (e.g. "10x20") into individual dimensions
  # Called automatically before every save via the before_save callback
  def parse_dimensions
    # `return if size.blank?` exits early (doing nothing further) when
    # there's no size string to parse, `.blank?` is a Rails helper
    # meaning nil, empty string, or whitespace-only.
    return if size.blank?

    # Split "10x20" into ["10", "20"] then convert to integers
    # `.downcase` normalizes case (so "10X20" and "10x20" both split the
    # same way), `.split("x")` breaks the string apart at each literal "x"
    # character, and `.map(&:to_i)` (see all_sizes above for `&:to_i`)
    # converts each resulting piece to an integer.
    parts = size.to_s.downcase.split("x").map(&:to_i)

    # Only proceed if we got exactly two positive numbers out of the split
    # (protects against malformed size strings like "10x" or "abc").
    if parts.length == 2 && parts[0] > 0 && parts[1] > 0
      # `self.width_ft = parts[0]` writes to this record's width_ft
      # attribute. The explicit `self.` here is necessary (not just
      # stylistic), without it, Ruby would treat `width_ft = ...` as
      # creating a new plain local variable named width_ft instead of
      # calling the width_ft= setter method that actually updates the
      # database attribute.
      self.width_ft = parts[0]   # First number is width
      self.depth_ft = parts[1]   # Second number is depth
      self.sqft     = parts[0] * parts[1]  # Square footage = width * depth
    else
      # Log a warning if we couldn't parse the size, this might mean the parser
      # is outputting size in an unexpected format
      # `id || 'new'`, `id` is nil for a record that hasn't been saved to
      # the database yet (no primary key assigned), so `||` ("or") falls
      # back to the literal string 'new' for a clearer log message in that
      # case, rather than logging a blank/nil id.
      Rails.logger.warn(
        "[Unit] Could not parse dimensions from size '#{size}' " \
        "on unit ##{id || 'new'} at facility ##{facility_id}"
      )
    end
    # `end` closes the `if parts.length == 2 && ... else ... end` block
    # above.
  end
  # `end` closes the `def parse_dimensions` method definition.
end
# `end` closes the `class Unit < ApplicationRecord` block that started at
# the top of the file.
