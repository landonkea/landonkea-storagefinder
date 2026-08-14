// =============================================================================
// FACILITY MAP CONTROLLER
// =============================================================================
// Renders the "Facility Map" panel on the dashboard: a Leaflet map with one
// pin per facility currently shown in the results table, colored to match
// the same green/yellow/red price bands used there (see Unit#price_color_class
// and app/views/dashboard/index.html.erb).
//
// The pin data itself comes from DashboardController#build_map_facilities,
// passed in via the "facilities" Stimulus value (a JSON-serialized array of
// plain { id, name, company, lat, lng, price, price_color, size, distance,
// address, maps_url } hashes, see the data-facility-map-facilities-value
// attribute on the #facility-map div in the dashboard view).
// =============================================================================

import { Controller } from "@hotwired/stimulus"
// Leaflet's vendored ESM build (vendor/javascript/leaflet.js, built from
// leaflet's own dist/leaflet-src.esm.js) only exports NAMED exports (map,
// marker, tileLayer, divIcon, Util, etc.), it has no `export default`. So
// this is a "namespace import" (`import * as L`), not a default import,
// even though the resulting `L.map(...)` / `L.marker(...)` call style
// looks identical to Leaflet's classic global-`L` usage.
import * as L from "leaflet"

// Maps each of the app's price-color CSS class names to a real color for
// the map pins (Leaflet's divIcon needs an actual color, not a CSS class
// applied to elsewhere-styled text), picked to match the emerald/yellow/
// red shades already used by those classes in app/assets/tailwind/application.css.
const PIN_COLORS = {
  "price-green":   "#34d399",
  "price-yellow":  "#facc15",
  "price-red":     "#f87171",
  "price-unknown": "#6b7280"
}

export default class extends Controller {
  // Declares one Stimulus "value": `facilitiesValue` is automatically
  // parsed from this element's `data-facility-map-facilities-value`
  // attribute (Stimulus's naming convention: controller identifier
  // "facility-map" + value name "facilities"). `type: Array` tells
  // Stimulus to JSON.parse the attribute string into a real array.
  static values = { facilities: Array }

  connect() {
    // Nothing to draw if there are no geocoded facilities to show,
    // avoids initializing an empty, blank map.
    if (!this.facilitiesValue || this.facilitiesValue.length === 0) return

    // `L.map(element)` creates a new Leaflet map attached to this
    // controller's own element (the div with data-controller="facility-map").
    this.map = L.map(this.element)

    // OpenStreetMap's free tile server, no API key required. Only the
    // background imagery needs network access; the pins/popups themselves
    // are drawn from data already in the page (see the importmap.rb
    // comment on the "leaflet" pin for more on this app's offline posture).
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "&copy; OpenStreetMap contributors",
      maxZoom: 19
    }).addTo(this.map)

    const bounds = []

    this.facilitiesValue.forEach((facility) => {
      const color = PIN_COLORS[facility.price_color] || PIN_COLORS["price-unknown"]

      // A small colored circle divIcon instead of Leaflet's default pin
      // image (see the note in app/assets/stylesheets/leaflet.css about
      // why the default marker images were never vendored).
      const icon = L.divIcon({
        className: "facility-map-pin",
        html: `<span style="display:block;width:14px;height:14px;border-radius:50%;background:${color};border:2px solid rgba(0,0,0,0.4);"></span>`,
        iconSize: [14, 14],
        iconAnchor: [7, 7]
      })

      const marker = L.marker([facility.lat, facility.lng], { icon }).addTo(this.map)

      // Leaflet has no built-in HTML-escaping helper, so this does it by
      // hand: prevents a facility name/address containing HTML-special
      // characters from breaking the popup markup or introducing an XSS
      // hole, since `bindPopup` below renders this as raw HTML.
      const escape = (value) => {
        const div = document.createElement("div")
        div.textContent = String(value ?? "")
        return div.innerHTML
      }

      const popupHtml = `
        <div style="min-width:160px">
          <div style="font-weight:600">${escape(facility.company)}</div>
          <div style="font-size:0.8em;color:#555;margin-bottom:4px">${escape(facility.name)}</div>
          <div style="display:flex;justify-content:space-between;gap:8px">
            <span>${escape(facility.size)}</span>
            <strong>${escape(facility.price)}</strong>
          </div>
          <div style="font-size:0.8em;color:#555">${escape(facility.distance)}</div>
          <div style="font-size:0.8em;color:#555">${escape(facility.address)}</div>
          ${facility.maps_url ? `<a href="${facility.maps_url}" target="_blank" rel="noopener" style="font-size:0.8em">Directions →</a>` : ""}
        </div>
      `
      marker.bindPopup(popupHtml)

      bounds.push([facility.lat, facility.lng])
    })

    // `fitBounds` zooms/pans the map so every pin is visible at once;
    // `padding` keeps pins from being drawn flush against the map's edge.
    // With only one facility, `fitBounds` on a single point zooms in too
    // far/oddly, so that case is handled separately below with `setView`.
    if (bounds.length === 1) {
      this.map.setView(bounds[0], 13)
    } else {
      this.map.fitBounds(bounds, { padding: [24, 24] })
    }
  }

  // Stimulus lifecycle callback, called automatically when this
  // controller's element is removed from the page (e.g. Turbo navigating
  // away). Leaflet doesn't clean up its own event listeners/DOM on its
  // own, so `remove()` here avoids leaking a map instance (and its tile
  // layer's event listeners) every time this page is visited.
  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }
}
