# =============================================================================
# PUBLIC SEARCH HELPER
# =============================================================================
# View helpers for the public search pages (app/views/public_search/*).
# =============================================================================
module PublicSearchHelper
  # Formats the live distance between a search origin point (lat/lng, e.g.
  # from the browser's geolocation or a geocoded address) and a facility, or
  # returns nil if there's no origin to measure from. Deliberately computed
  # live via the geocoder gem's own distance calculation (the same one
  # Facility.calculate_distances_from uses in app/models/facility.rb) rather
  # than reading Facility#distance_miles, which only reflects the LAST
  # crawl's fixed search origin, a customer's search location here is
  # different every request.
  def distance_from_origin(facility, origin)
    return nil if origin.nil? || facility.latitude.nil? || facility.longitude.nil?

    miles = Geocoder::Calculations.distance_between(
      [ origin[:lat], origin[:lng] ],
      [ facility.latitude, facility.longitude ],
      units: :mi
    )
    "#{"%.1f" % miles} miles away"
  end

  # Both maps_url (built from an address, see Facility#maps_url) and
  # booking_url (scraped from a company's own website, see
  # app/lib/companies/) end up in a `link_to ... href` on the facility
  # detail page. Since booking_url in particular is third-party-scraped
  # text rather than something this app fully controls, this guard makes
  # sure only an ordinary http(s) link is ever rendered as a clickable
  # href, never something like a "javascript:" URI a broken/malicious
  # scrape could otherwise sneak through.
  def safe_external_url?(url)
    url.present? && url.match?(%r{\Ahttps?://}i)
  end
end
