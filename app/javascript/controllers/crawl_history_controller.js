// =============================================================================
// CRAWL HISTORY CONTROLLER
// =============================================================================
// Handles the "select all" checkbox and "Delete Selected" button in the
// dashboard's crawl history panel (app/views/dashboard/_crawl_history.html.erb).
// =============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "rowCheckbox", "bulkDeleteButton"]

  // Called when the header "select all" checkbox is toggled
  toggleAll(event) {
    this.rowCheckboxTargets.forEach(checkbox => {
      checkbox.checked = event.target.checked
    })

    this.refreshButtonState()
  }

  // Called when any individual row checkbox is toggled
  toggleRow() {
    // If every row is checked, reflect that in the "select all" checkbox too
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked =
        this.rowCheckboxTargets.length > 0 &&
        this.rowCheckboxTargets.every(checkbox => checkbox.checked)
    }

    this.refreshButtonState()
  }

  // Enable "Delete Selected" only once at least one row is checked
  refreshButtonState() {
    const anyChecked = this.rowCheckboxTargets.some(checkbox => checkbox.checked)
    this.bulkDeleteButtonTarget.disabled = !anyChecked
  }
}
