# =============================================================================
# GEOCODER CONFIGURATION
# =============================================================================
# Geocoder converts city names and addresses to GPS coordinates.
# We use Nominatim (OpenStreetMap) which is FREE and requires no API key.
#
# Nominatim rate limit: max 1 request per second — we add a small delay
# to respect this. If you need faster geocoding or higher limits,
# you can sign up for a free Google Geocoding API key and switch to :google.
# =============================================================================

Geocoder.configure(
  # Use OpenStreetMap's Nominatim geocoding service — free, no API key
  lookup:  :nominatim,

  # Use IP info for IP address lookups (not used in StorageFinder but good to set)
  ip_lookup: :ipinfo_io,

  # Nominatim requires a User-Agent identifying your app
  # Without this, requests will be rejected
  http_headers: {
    "User-Agent" => "StorageFinder/1.0 (self-hosted LAN storage price tracker)"
  },

  # Timeout for geocoding requests (seconds)
  timeout: 10,

  # Cache geocoding results in Rails cache to avoid re-geocoding the same city
  # This respects Nominatim's rate limit by not re-requesting recently seen addresses
  cache: Rails.cache,
  cache_options: {
    expiration: 1.day,    # How long to cache a geocoding result
    prefix:     "storagefinder:geocoder:"
  },

  # Units for distance calculations
  units: :mi,  # miles

  # Whether to throw exceptions on geocoding failure
  # false = return empty array on failure (safer)
  always_raise: []
)

Rails.logger.info("[Geocoder] Configured with Nominatim (OpenStreetMap) — no API key required")
