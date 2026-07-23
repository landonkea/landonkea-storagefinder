# =============================================================================
# FACILITY MODEL
# =============================================================================
# A Facility represents one physical storage location.
# It has a company name, address, GPS coordinates, and many units.
#
# Example: "Extra Space Storage at 1234 E Ray Rd, Gilbert AZ 85296"
# =============================================================================

# `class Facility < ApplicationRecord` defines a Ruby class named Facility
# that inherits from ApplicationRecord (see app/models/application_record.rb).
# Inheriting from ApplicationRecord makes this an "ActiveRecord model": each
# instance of Facility represents one row of the "facilities" database
# table, and every column (company, address, latitude, ...) is automatically
# readable/writable as a plain Ruby attribute, e.g. `facility.company`.
class Facility < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  # has_many means: "one facility has many units"
  # dependent: :destroy means: if we delete a facility, delete all its units too
  # ---------------------------------------------------------------------------
  # `has_many :units` generates a `facility.units` method that queries and
  # returns every Unit row whose `facility_id` column points at this
  # particular Facility. `dependent: :destroy` tells Rails to automatically
  # delete all those related Unit rows first whenever this Facility is
  # deleted, so no Unit is left pointing at a facility_id that no longer
  # exists.
  has_many :units, dependent: :destroy

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # Validations are rules that must pass before a record can be saved.
  # If a validation fails, Rails refuses to save and returns an error message.
  # ---------------------------------------------------------------------------
  # Each `validates :column, presence: { message: "..." }` line requires
  # that column to be present (not nil, not blank) before a save succeeds,
  # and customizes the message shown if it isn't.
  validates :company, presence: { message: "Company name is required" }
  validates :name,    presence: { message: "Facility name is required" }
  validates :address, presence: { message: "Address is required" }
  validates :city,    presence: { message: "City is required" }
  validates :state,   presence: { message: "State is required" }
  validates :zip,     presence: { message: "ZIP code is required" }

  # ZIP code must be either 5 digits or 5+4 format (e.g. 85296 or 85296-1234)
  # `format:` validates the value against a regular expression (a pattern
  # for matching text). `/\A\d{5}(-\d{4})?\z/` reads as: `\A` = start of
  # string, `\d{5}` = exactly 5 digits, `(-\d{4})?` = an OPTIONAL group
  # (the trailing `?` on the group makes it optional) consisting of a
  # literal hyphen followed by 4 more digits, `\z` = end of string. So it
  # matches "85296" or "85296-1234" but rejects anything else.
  # `allow_blank: true` skips this format check entirely when zip is blank
  # (that case is already covered by the separate presence validation above).
  validates :zip, format: {
    with:    /\A\d{5}(-\d{4})?\z/,
    message: "ZIP must be 5 digits or ZIP+4 format (e.g. 85296)"
  }, allow_blank: true

  # Mirrors Companies::BaseParser#upsert_facility's dedup logic (matching by
  # external_id when present, otherwise by address+city+state), backed by a
  # real unique index in the database (see the add_facility_uniqueness_indexes
  # migration) — these validations just turn a raw constraint violation into
  # a readable error message instead of an ActiveRecord::RecordNotUnique.
  #
  # `uniqueness:` validates that no OTHER existing row already has this same
  # value (or combination of values, via `scope:`). `scope: :company` means
  # external_id only has to be unique WITHIN rows sharing the same company —
  # two different companies could reuse the same external_id without
  # conflict. `allow_nil: true` skips this check when external_id is nil.
  validates :external_id, uniqueness: {
    scope:   :company,
    message: "already has a facility with this external ID for this company"
  }, allow_nil: true
  # Similarly, `address` must be unique within the combination of
  # `[:company, :city, :state]` — `scope:` accepts an array here to scope
  # uniqueness across multiple columns at once. `if: -> { external_id.blank? }`
  # is a conditional lambda (see app/models/alert_rule.rb for more on `if:`
  # lambdas) — this address-uniqueness check only runs when there's no
  # external_id to rely on instead.
  validates :address, uniqueness: {
    scope:   [ :company, :city, :state ],
    message: "already has a facility at this address for this company"
  }, if: -> { external_id.blank? }

  # ---------------------------------------------------------------------------
  # GEOCODER
  # ---------------------------------------------------------------------------
  # This tells the geocoder gem which address fields to use for geocoding,
  # and where to store the resulting lat/lng coordinates.
  # ---------------------------------------------------------------------------
  # `geocoded_by` comes from the "geocoder" Ruby gem (a third-party library
  # this app depends on for turning street addresses into GPS coordinates).
  # It tells the gem to call the `geocodable_address` instance method
  # (defined further down this file) to get the address string to look up,
  # and — by convention — to store the resulting latitude/longitude into
  # this model's `latitude`/`longitude` columns.
  geocoded_by :geocodable_address     # The method to call to get the address string
  # `after_validation` is a Rails "callback" — a hook that runs a method
  # automatically at a specific point in a record's lifecycle (here, right
  # after validations run but before the record is saved). `:geocode` is
  # a method the geocoder gem adds to this model, which performs the actual
  # network lookup and fills in latitude/longitude.
  after_validation :geocode,          # After validating, automatically look up coordinates
    # Re-geocode when the address changes, or retry when a previous attempt
    # never got coordinates (e.g. a transient Nominatim failure) — otherwise
    # a facility whose first geocode call failed would stay "Unknown"
    # forever, since re-crawls save the same, unchanged address.
    #
    # `if:` (same conditional-lambda pattern as in AlertRule/Facility's
    # validations above) means the geocode callback only actually runs when
    # this lambda returns true. `address_changed?` is an automatically
    # generated Rails "dirty tracking" method — true if the `address`
    # attribute has been modified since the record was loaded/last saved.
    if: -> { address_changed? || latitude.nil? }

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  # Scopes are named, reusable database queries.
  # You call them like: Facility.within_miles(50, lat, lng)
  # ---------------------------------------------------------------------------

  # Returns facilities sorted by distance from a given point
  # Usage: Facility.nearest_to(33.3528, -111.7890)
  #
  # `->(lat, lng) { ... }` is a lambda taking two positional arguments.
  scope :nearest_to, ->(lat, lng) {
    # `where.not(latitude: nil, longitude: nil)` excludes any facility
    # missing coordinates — you can't sort by distance without them.
    where.not(latitude: nil, longitude: nil)
      # `.order(...)` sorts the query results; here it's given a raw SQL
      # expression (see below) instead of a simple column name, so the
      # database itself computes a distance value per row and sorts by it.
      .order(
        # Haversine formula — calculates great-circle distance between two GPS points
        # This SQL runs inside SQLite and returns distance in miles
        # `Arel.sql(...)` wraps a raw SQL string so Rails will insert it
        # into the query literally instead of trying to treat it as an
        # unsafe, escapable value — necessary here because we're building a
        # full mathematical SQL expression, not just a plain column/value.
        Arel.sql(
          # `#{lat.to_f}` / `#{lng.to_f}` interpolate the lambda's `lat`/`lng`
          # arguments directly into the SQL string as plain numbers
          # (`.to_f` converts to a float) — the `\` at the end of each
          # string line is Ruby's line-continuation syntax, joining these
          # three lines into one long SQL string with no added newlines.
          "((acos(sin(#{lat.to_f} * pi() / 180) * sin(latitude * pi() / 180) + " \
          "cos(#{lat.to_f} * pi() / 180) * cos(latitude * pi() / 180) * " \
          "cos((#{lng.to_f} - longitude) * pi() / 180)) * 180 / pi()) * 60 * 1.1515)"
        )
      )
  }

  # Returns only facilities that have geocoded coordinates
  scope :geocoded,    -> { where.not(latitude: nil, longitude: nil) }

  # Returns facilities for a specific company
  # Usage: Facility.for_company("Extra Space Storage")
  scope :for_company, ->(company) { where(company: company) }

  # Returns facilities in a specific city
  scope :in_city,     ->(city) { where(city: city) }

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------
  # Everything below (until CLASS METHODS) is a regular Ruby method callable
  # on one particular Facility record, e.g. `some_facility.full_address`.

  # Returns the full address as a single string for geocoding
  # Example: "1234 E Ray Rd, Gilbert, AZ 85296"
  #
  # String interpolation (`#{...}`) inserts each attribute's value into the
  # surrounding string; this is the method's return value since it's the
  # last (and only) expression evaluated.
  def full_address
    "#{address}, #{city}, #{state} #{zip}"
  end
  # `end` closes the `def full_address` method definition.

  # Address string used for geocoding only. Suite/unit numbers (e.g. "Ste 100",
  # "Suite B", "#4") make Nominatim return no match at all even though the
  # base street address geocodes fine — strip them here. full_address (with
  # the suite number) is still what's shown to users and used for map links.
  def geocodable_address
    # `address.to_s` ensures we have a string even if address were
    # unexpectedly nil (`.to_s` on nil returns ""). `.gsub(pattern, "")`
    # replaces every match of the regular expression with an empty string
    # (i.e. deletes matches). The pattern
    # `/\s*(?:ste|suite|unit|#)\.?\s*[\w-]+\s*$/i` matches, at the END of
    # the address (`$`): optional whitespace, then one of the words
    # "ste"/"suite"/"unit" or a literal "#" (the `(?:...)` is a
    # "non-capturing group" — it groups alternatives with `|` for "or"
    # without creating a numbered capture), an optional period, more
    # optional whitespace, then a run of word-characters/hyphens (the
    # actual suite number/letter), then trailing whitespace. The `i` flag
    # after the closing `/` makes the match case-insensitive (so "Ste",
    # "STE", "ste" all match). `.strip` then trims any leftover leading/
    # trailing whitespace after the removal.
    stripped_address = address.to_s.gsub(/\s*(?:ste|suite|unit|#)\.?\s*[\w-]+\s*$/i, "").strip
    # Builds the final geocoding string using the stripped address instead
    # of the raw `address` attribute, keeping city/state/zip unchanged.
    "#{stripped_address}, #{city}, #{state} #{zip}"
  end
  # `end` closes the `def geocodable_address` method definition.

  # Returns the cheapest unit currently available at this facility
  # Used in the dashboard to show the "starting price" for each facility
  def cheapest_available_unit
    # `units` calls the has_many association defined near the top of this
    # file, returning a query scoped to this facility's units. `.where(
    # available: true)` filters to only available ones. `.order(
    # :monthly_price)` sorts ascending (cheapest first) by default.
    # `.first` takes just the single cheapest one (or nil if there are none).
    units.where(available: true).order(:monthly_price).first
  end
  # `end` closes the `def cheapest_available_unit` method definition.

  # Returns the cheapest price available at this facility
  # Returns nil if no units are available
  def min_price
    # `&.` is Ruby's "safe navigation" operator: it calls `.monthly_price`
    # only if `cheapest_available_unit` returned a real Unit; if it
    # returned nil (no available units), the whole expression short-
    # circuits to nil instead of raising a NoMethodError.
    cheapest_available_unit&.monthly_price
  end
  # `end` closes the `def min_price` method definition.

  # Returns a formatted distance string like "3.2 miles"
  # Returns "Unknown" if we don't have distance data
  def distance_label
    return "Unknown" if distance_miles.nil?
    # `"%.1f" % distance_miles` uses Ruby's `%` string-formatting operator
    # (similar to C's printf): `%.1f` means "format as a floating-point
    # number with exactly 1 digit after the decimal point." The result is
    # then interpolated into the surrounding string with `#{...}`.
    "#{"%.1f" % distance_miles} miles"
  end
  # `end` closes the `def distance_label` method definition.

  # Returns how many units are currently available at this facility
  def available_unit_count
    # `.count` runs an efficient SQL COUNT query rather than loading every
    # matching Unit row into memory just to measure how many there are.
    units.where(available: true).count
  end
  # `end` closes the `def available_unit_count` method definition.

  # Returns true if this facility has any climate-controlled units
  def has_climate_control?
    # `.exists?` runs an efficient SQL existence check (like `any_running?`
    # in CrawlRun) — it returns true/false without loading matching rows.
    units.where(climate_controlled: true).exists?
  end
  # `end` closes the `def has_climate_control?` method definition.

  # Returns a Google Maps URL for this facility's address
  def maps_url
    # `URI.encode_www_form_component(...)` is Ruby's standard-library
    # helper for URL-encoding a string so it's safe to embed in a URL query
    # parameter — e.g. spaces become "+" and special characters are
    # percent-escaped, since raw addresses often contain spaces and commas
    # that aren't valid unescaped in a URL.
    encoded_address = URI.encode_www_form_component(full_address)
    "https://www.google.com/maps/search/?api=1&query=#{encoded_address}"
  end
  # `end` closes the `def maps_url` method definition.

  # Returns a formatted phone number like "(480) 555-1234"
  # Falls back to raw phone if it can't be formatted
  def formatted_phone
    # `.blank?` is a Rails helper meaning nil, empty string, or
    # whitespace-only — the opposite of `.present?`. Returns nil early if
    # there's no phone number to format at all.
    return nil if phone.blank?

    # Strip everything except digits
    # `.gsub(/\D/, "")` replaces every character matched by `\D` ("any
    # character that is NOT a digit") with nothing — i.e. deletes all
    # non-digit characters, leaving just the raw digits.
    digits = phone.gsub(/\D/, "")

    # Format as (XXX) XXX-XXXX if we have 10 digits
    if digits.length == 10
      # `digits[0..2]` is Ruby's range-based string slicing: characters at
      # index 0 through 2 inclusive (the first 3 characters). Similarly
      # `digits[3..5]` is the next 3, and `digits[6..9]` is the last 4 —
      # together forming a standard US phone number layout.
      "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
    elsif digits.length == 11 && digits[0] == "1"
      # Handle 1-XXX-XXX-XXXX format
      # Same slicing idea, but shifted by one character to skip the
      # leading country-code "1" digit at index 0.
      "(#{digits[1..3]}) #{digits[4..6]}-#{digits[7..10]}"
    else
      phone  # Return original if we can't parse it
    end
    # `end` closes the `if/elsif/else` block above; its result is this
    # method's return value.
  end
  # `end` closes the `def formatted_phone` method definition.

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------
  # `def self.method_name` defines a CLASS method — called on the class
  # itself (e.g. `Facility.all_companies`) rather than on one record.

  # Returns an array of all unique company names in the database
  # Used to populate the company filter dropdown
  def self.all_companies
    # `distinct` tells the database query to eliminate duplicate rows.
    # `.pluck(:company)` runs an efficient SQL query that fetches ONLY the
    # `company` column (not whole Facility objects) as a plain Ruby array
    # of strings. `.sort` then sorts that array alphabetically.
    distinct.pluck(:company).sort
  end
  # `end` closes the `def self.all_companies` class method definition.

  # Returns an array of all unique cities in the database
  def self.all_cities
    distinct.pluck(:city).sort
  end
  # `end` closes the `def self.all_cities` class method definition.

  # Calculates and stores the distance_miles for all geocoded facilities
  # relative to a given origin point.
  # Call this after a crawl completes.
  def self.calculate_distances_from(origin_lat, origin_lng)
    # Make sure we have valid coordinates to calculate from
    if origin_lat.nil? || origin_lng.nil?
      Rails.logger.error("[Facility] Cannot calculate distances — origin coordinates are nil")
      # A bare `return` with no value exits the method early, doing
      # nothing further, when the origin coordinates are missing.
      return
    end
    # `end` closes the `if origin_lat.nil? || origin_lng.nil?` block above.

    # `geocoded` calls the scope defined earlier in this file (facilities
    # with non-nil lat/lng). `.find_each` is a Rails method for iterating
    # over a LARGE number of records in memory-efficient batches (loading
    # them a chunk at a time from the database instead of all at once),
    # rather than plain `.each` which would load every matching record
    # into memory simultaneously. `do |facility| ... end` is a Ruby block —
    # a chunk of code passed to `find_each`, run once per record, with that
    # record available inside the block as the local variable `facility`.
    geocoded.find_each do |facility|
      # `begin ... rescue ... end` is Ruby's exception-handling structure:
      # code in the `begin` block runs normally; if it raises an error, the
      # matching `rescue` block below runs instead of crashing the whole
      # method, letting the loop continue with the next facility.
      begin
        # Geocoder gem's built-in distance calculation
        # Returns distance in miles between two lat/lng pairs
        # `[ origin_lat, origin_lng ]` and `[ facility.latitude,
        # facility.longitude ]` are two-element Ruby arrays representing
        # coordinate pairs, passed to the geocoder gem's distance-
        # calculation helper. `units: :mi` is a keyword argument telling it
        # to return the result in miles (as opposed to kilometers).
        distance = Geocoder::Calculations.distance_between(
          [ origin_lat, origin_lng ],
          [ facility.latitude, facility.longitude ],
          units: :mi
        )

        # Round to 1 decimal place and save
        # `update_column` (like in AlertRule#record_triggered!) writes
        # directly to the database column, skipping validations/callbacks —
        # appropriate here since this is a simple derived/calculated value,
        # not user input that needs validating.
        facility.update_column(:distance_miles, distance.round(1))

      # `rescue => e` catches any standard error raised inside the `begin`
      # block above and stores it in the local variable `e`.
      rescue => e
        # Log the error but keep going — one bad facility shouldn't stop everything
        # `e.message` reads the human-readable description of what went
        # wrong from the caught exception object.
        Rails.logger.warn(
          "[Facility] Could not calculate distance for facility ##{facility.id} " \
          "(#{facility.name}): #{e.message}"
        )
      end
      # `end` closes the `begin/rescue` block for this one facility.
    end
    # `end` closes the `do |facility| ... end` block passed to `find_each`.

    Rails.logger.info("[Facility] Distance calculation complete for #{geocoded.count} facilities")
  end
  # `end` closes the `def self.calculate_distances_from` class method
  # definition.
end
# `end` closes the `class Facility < ApplicationRecord` block that started
# at the top of the file.
