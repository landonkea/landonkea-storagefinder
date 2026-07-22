# =============================================================================
# FACILITY MODEL
# =============================================================================
# A Facility represents one physical storage location.
# It has a company name, address, GPS coordinates, and many units.
#
# Example: "Extra Space Storage at 1234 E Ray Rd, Gilbert AZ 85296"
# =============================================================================

class Facility < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  # has_many means: "one facility has many units"
  # dependent: :destroy means: if we delete a facility, delete all its units too
  # ---------------------------------------------------------------------------
  has_many :units, dependent: :destroy

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  # Validations are rules that must pass before a record can be saved.
  # If a validation fails, Rails refuses to save and returns an error message.
  # ---------------------------------------------------------------------------
  validates :company, presence: { message: "Company name is required" }
  validates :name,    presence: { message: "Facility name is required" }
  validates :address, presence: { message: "Address is required" }
  validates :city,    presence: { message: "City is required" }
  validates :state,   presence: { message: "State is required" }
  validates :zip,     presence: { message: "ZIP code is required" }

  # ZIP code must be either 5 digits or 5+4 format (e.g. 85296 or 85296-1234)
  validates :zip, format: {
    with:    /\A\d{5}(-\d{4})?\z/,
    message: "ZIP must be 5 digits or ZIP+4 format (e.g. 85296)"
  }, allow_blank: true

  # Mirrors Companies::BaseParser#upsert_facility's dedup logic (matching by
  # external_id when present, otherwise by address+city+state), backed by a
  # real unique index in the database (see the add_facility_uniqueness_indexes
  # migration) — these validations just turn a raw constraint violation into
  # a readable error message instead of an ActiveRecord::RecordNotUnique.
  validates :external_id, uniqueness: {
    scope:   :company,
    message: "already has a facility with this external ID for this company"
  }, allow_nil: true
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
  geocoded_by :geocodable_address     # The method to call to get the address string
  after_validation :geocode,          # After validating, automatically look up coordinates
    # Re-geocode when the address changes, or retry when a previous attempt
    # never got coordinates (e.g. a transient Nominatim failure) — otherwise
    # a facility whose first geocode call failed would stay "Unknown"
    # forever, since re-crawls save the same, unchanged address.
    if: -> { address_changed? || latitude.nil? }

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------
  # Scopes are named, reusable database queries.
  # You call them like: Facility.within_miles(50, lat, lng)
  # ---------------------------------------------------------------------------

  # Returns facilities sorted by distance from a given point
  # Usage: Facility.nearest_to(33.3528, -111.7890)
  scope :nearest_to, ->(lat, lng) {
    where.not(latitude: nil, longitude: nil)
      .order(
        # Haversine formula — calculates great-circle distance between two GPS points
        # This SQL runs inside SQLite and returns distance in miles
        Arel.sql(
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

  # Returns the full address as a single string for geocoding
  # Example: "1234 E Ray Rd, Gilbert, AZ 85296"
  def full_address
    "#{address}, #{city}, #{state} #{zip}"
  end

  # Address string used for geocoding only. Suite/unit numbers (e.g. "Ste 100",
  # "Suite B", "#4") make Nominatim return no match at all even though the
  # base street address geocodes fine — strip them here. full_address (with
  # the suite number) is still what's shown to users and used for map links.
  def geocodable_address
    stripped_address = address.to_s.gsub(/\s*(?:ste|suite|unit|#)\.?\s*[\w-]+\s*$/i, "").strip
    "#{stripped_address}, #{city}, #{state} #{zip}"
  end

  # Returns the cheapest unit currently available at this facility
  # Used in the dashboard to show the "starting price" for each facility
  def cheapest_available_unit
    units.where(available: true).order(:monthly_price).first
  end

  # Returns the cheapest price available at this facility
  # Returns nil if no units are available
  def min_price
    cheapest_available_unit&.monthly_price
  end

  # Returns a formatted distance string like "3.2 miles"
  # Returns "Unknown" if we don't have distance data
  def distance_label
    return "Unknown" if distance_miles.nil?
    "#{"%.1f" % distance_miles} miles"
  end

  # Returns how many units are currently available at this facility
  def available_unit_count
    units.where(available: true).count
  end

  # Returns true if this facility has any climate-controlled units
  def has_climate_control?
    units.where(climate_controlled: true).exists?
  end

  # Returns a Google Maps URL for this facility's address
  def maps_url
    encoded_address = URI.encode_www_form_component(full_address)
    "https://www.google.com/maps/search/?api=1&query=#{encoded_address}"
  end

  # Returns a formatted phone number like "(480) 555-1234"
  # Falls back to raw phone if it can't be formatted
  def formatted_phone
    return nil if phone.blank?

    # Strip everything except digits
    digits = phone.gsub(/\D/, "")

    # Format as (XXX) XXX-XXXX if we have 10 digits
    if digits.length == 10
      "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
    elsif digits.length == 11 && digits[0] == "1"
      # Handle 1-XXX-XXX-XXXX format
      "(#{digits[1..3]}) #{digits[4..6]}-#{digits[7..10]}"
    else
      phone  # Return original if we can't parse it
    end
  end

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------

  # Returns an array of all unique company names in the database
  # Used to populate the company filter dropdown
  def self.all_companies
    distinct.pluck(:company).sort
  end

  # Returns an array of all unique cities in the database
  def self.all_cities
    distinct.pluck(:city).sort
  end

  # Calculates and stores the distance_miles for all geocoded facilities
  # relative to a given origin point.
  # Call this after a crawl completes.
  def self.calculate_distances_from(origin_lat, origin_lng)
    # Make sure we have valid coordinates to calculate from
    if origin_lat.nil? || origin_lng.nil?
      Rails.logger.error("[Facility] Cannot calculate distances — origin coordinates are nil")
      return
    end

    geocoded.find_each do |facility|
      begin
        # Geocoder gem's built-in distance calculation
        # Returns distance in miles between two lat/lng pairs
        distance = Geocoder::Calculations.distance_between(
          [ origin_lat, origin_lng ],
          [ facility.latitude, facility.longitude ],
          units: :mi
        )

        # Round to 1 decimal place and save
        facility.update_column(:distance_miles, distance.round(1))

      rescue => e
        # Log the error but keep going — one bad facility shouldn't stop everything
        Rails.logger.warn(
          "[Facility] Could not calculate distance for facility ##{facility.id} " \
          "(#{facility.name}): #{e.message}"
        )
      end
    end

    Rails.logger.info("[Facility] Distance calculation complete for #{geocoded.count} facilities")
  end
end
