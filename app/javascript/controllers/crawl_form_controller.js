// =============================================================================
// CRAWL FORM CONTROLLER
// =============================================================================
// Handles the "Run Crawl" form interactions:
//   - Toggle all company checkboxes at once
//   - Validate required fields before submit
// =============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // Called when the user clicks "Toggle all" next to company checkboxes
  toggleAllCompanies(event) {
    event.preventDefault()

    // Find all company checkboxes in this form
    const checkboxes = this.element.querySelectorAll("input[name='companies[]']")

    // If all are checked, uncheck all. If any are unchecked, check all.
    const allChecked = Array.from(checkboxes).every(cb => cb.checked)

    checkboxes.forEach(cb => {
      cb.checked = !allChecked  // Flip the state
    })
  }

  // Called when the form is submitted — do a quick client-side check
  // before letting the request go to the server
  submit(event) {
    const cityField = this.element.querySelector("input[name='search_city']")

    if (!cityField || cityField.value.trim() === "") {
      event.preventDefault()  // Stop the form from submitting
      alert("Please enter a city name or ZIP code.")
      cityField?.focus()
      return
    }

    const checkboxes = this.element.querySelectorAll("input[name='companies[]']:checked")
    if (checkboxes.length === 0) {
      event.preventDefault()
      alert("Please select at least one company to crawl.")
      return
    }

    // Disable the submit button so the user can't double-click and start two crawls
    const submitBtn = this.element.querySelector("button[type='submit']")
    if (submitBtn) {
      submitBtn.disabled = true
      submitBtn.textContent = "Starting crawl..."
    }
  }
}
