# =============================================================================
# STORAMERICA PARSER — STUB (not yet implemented)
# =============================================================================
# Run: rails runner "ReconService.run('https://www.storamerica.com/locations/')"
# then implement parse_locations/parse_units based on the recon report.
# =============================================================================

class Companies::StorAmerica < Companies::BaseParser
  RECON_URL = "https://www.storamerica.com/locations/"

  def company_name  = "StorAmerica"
  def company_slug  = "storamerica"

  def search_url(lat, lng, radius_miles)
    "https://www.storamerica.com/locations/?lat=#{lat}&lng=#{lng}"
  end

  def parse_locations(page)
    log_warning(
      "StorAmerica parser is a STUB. " \
      "Run: rails runner \"ReconService.run('#{RECON_URL}')\" to generate selectors."
    )
    []
  end

  def parse_units(page, facility) = []
end
