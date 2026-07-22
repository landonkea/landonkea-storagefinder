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

class Unit < ApplicationRecord
  # ---------------------------------------------------------------------------
  # ASSOCIATIONS
  # ---------------------------------------------------------------------------
  belongs_to :facility   # Every unit must belong to a facility
  belongs_to :crawl_run  # Every unit must be associated with the crawl that found it

  # ---------------------------------------------------------------------------
  # VALIDATIONS
  # ---------------------------------------------------------------------------
  validates :size,         presence: { message: "Unit size is required (e.g. 10x10)" }
  validates :collected_at, presence: { message: "Collection timestamp is required" }

  # Size must match a pattern like "10x10", "10x20", "12x30", etc.
  validates :size, format: {
    with:    /\A\d+x\d+\z/i,
    message: "Size must be in WIDTHxDEPTH format (e.g. 10x10, 10x20)"
  }, allow_blank: true

  # Price must be positive if provided
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
  before_save :parse_dimensions

  # ---------------------------------------------------------------------------
  # SCOPES
  # ---------------------------------------------------------------------------

  # Only units that are currently available for rent
  scope :available,          -> { where(available: true) }

  # Only climate-controlled units
  scope :climate_controlled, -> { where(climate_controlled: true) }

  # Exclude unit types we don't care about (parking, RV, boat, etc.)
  scope :enclosed,           -> { where(indoor: true, drive_up: false) }

  # Filter by minimum size
  # Usage: Unit.at_least_size(10, 10) — returns all units 10x10 or larger
  scope :at_least_size, ->(min_width, min_depth) {
    where("width_ft >= ? AND depth_ft >= ?", min_width, min_depth)
  }

  # Filter to specific sizes (array of size strings)
  # Usage: Unit.with_sizes(["10x10", "10x20"])
  scope :with_sizes, ->(sizes) {
    where(size: sizes) if sizes.present?
  }

  # Exclude specific unit types
  scope :exclude_types, ->(types) {
    where.not(unit_type: types) if types.present?
  }

  # Sort by cheapest price first
  scope :cheapest_first,   -> { order(monthly_price: :asc) }

  # Sort by largest unit first (by square footage)
  scope :largest_first,    -> { order(sqft: :desc) }

  # Only units collected in the most recent crawl run
  scope :from_latest_crawl, -> {
    latest_run = CrawlRun.completed.order(completed_at: :desc).first
    return none unless latest_run  # Return empty if no crawl has been run
    where(crawl_run: latest_run)
  }

  # Units from the last N days (for history/trend queries)
  scope :since,            ->(date) { where("collected_at >= ?", date) }

  # ---------------------------------------------------------------------------
  # UNIT TYPE CONSTANTS
  # ---------------------------------------------------------------------------
  # These are the unit types we actively EXCLUDE from results by default.
  # Parser modules should tag units with these types so filters work correctly.
  # ---------------------------------------------------------------------------
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
  MIN_WIDTH_FT = 10
  MIN_DEPTH_FT = 10

  # ---------------------------------------------------------------------------
  # INSTANCE METHODS
  # ---------------------------------------------------------------------------

  # Returns the display price — use web special if it's lower than regular price
  # This is what gets shown on the dashboard as the "best price"
  def best_price
    # Safely handle nil monthly_price — return web_special if it exists, else monthly
    if web_special_price.present? && (monthly_price.nil? || web_special_price < monthly_price.to_d)
      web_special_price
    else
      monthly_price
    end
  end

  # Returns true if this unit has a web special that's lower than the regular price
  def has_web_special?
    web_special_price.present? && web_special_price < monthly_price.to_d
  end

  # Returns a formatted price string like "$89.00" or "Not listed"
  def formatted_price
    return "Not listed" if monthly_price.nil?
    "$#{"%.2f" % monthly_price}"
  end

  # Returns a formatted web special price like "$79.00" or nil
  def formatted_web_special
    return nil unless has_web_special?
    "$#{"%.2f" % web_special_price}"
  end

  # Returns a CSS color class for the price (green/yellow/red)
  # Used in the dashboard table to color-code cells
  def price_color_class
    return "price-unknown" if best_price.nil?

    case best_price
    when ..99.99   then "price-green"   # Under $100
    when 100..149  then "price-yellow"  # $100-$149
    else                "price-red"     # $150+
    end
  end

  # Returns the square footage as a formatted string like "200 sq ft"
  def sqft_label
    return "Unknown" if sqft.nil?
    "#{sqft} sq ft"
  end

  # Returns true if this unit meets the standard filter criteria
  def matches_default_filters?
    climate_controlled &&
      indoor &&
      !drive_up &&
      EXCLUDED_TYPES.exclude?(unit_type.to_s.downcase) &&
      width_ft.to_i >= MIN_WIDTH_FT &&
      depth_ft.to_i >= MIN_DEPTH_FT
  end

  # ---------------------------------------------------------------------------
  # CLASS METHODS
  # ---------------------------------------------------------------------------

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
  def self.apply_filters(filter_options = {})
    scope = all  # Start with all units, then chain filters

    # Filter by climate control
    if filter_options[:climate_controlled].present?
      scope = scope.where(climate_controlled: filter_options[:climate_controlled])
    end

    # Filter by specific sizes
    if filter_options[:sizes].present?
      scope = scope.where(size: filter_options[:sizes])
    end

    # Filter by minimum size
    if filter_options[:min_width].present? && filter_options[:min_depth].present?
      scope = scope.where(
        "width_ft >= ? AND depth_ft >= ?",
        filter_options[:min_width].to_i,
        filter_options[:min_depth].to_i
      )
    end

    # Exclude specific unit types
    if filter_options[:exclude_types].present?
      scope = scope.where.not(unit_type: filter_options[:exclude_types])
    end

    # Exclude drive-up/outdoor units by default
    unless filter_options[:include_drive_up]
      scope = scope.where(drive_up: false)
    end

    # Only available units by default
    unless filter_options[:include_unavailable]
      scope = scope.where(available: true)
    end

    # Only indoor units by default
    unless filter_options[:include_outdoor]
      scope = scope.where(indoor: true)
    end

    scope
  end

  # Returns all unique sizes present in the database, sorted logically
  # Used to populate the size filter checkboxes
  def self.all_sizes
    pluck(:size).uniq.sort_by do |s|
      # Sort by total square footage (width * depth) so 10x10 comes before 10x20
      parts = s.to_s.split("x").map(&:to_i)
      parts[0].to_i * parts[1].to_i rescue 0
    end
  end

  # ---------------------------------------------------------------------------
  # PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  # Parse the size string (e.g. "10x20") into individual dimensions
  # Called automatically before every save via the before_save callback
  def parse_dimensions
    return if size.blank?

    # Split "10x20" into ["10", "20"] then convert to integers
    parts = size.to_s.downcase.split("x").map(&:to_i)

    if parts.length == 2 && parts[0] > 0 && parts[1] > 0
      self.width_ft = parts[0]   # First number is width
      self.depth_ft = parts[1]   # Second number is depth
      self.sqft     = parts[0] * parts[1]  # Square footage = width * depth
    else
      # Log a warning if we couldn't parse the size — this might mean the parser
      # is outputting size in an unexpected format
      Rails.logger.warn(
        "[Unit] Could not parse dimensions from size '#{size}' " \
        "on unit ##{id || 'new'} at facility ##{facility_id}"
      )
    end
  end
end
