// =============================================================================
// JAVASCRIPT ENTRY POINT
// =============================================================================
// Rails loads this file first via the importmap.
// It sets up Turbo, Stimulus, ActionCable, and global utilities.
// =============================================================================

// Turbo — makes page navigation fast by replacing only changed content
// (page transitions feel instant without a full reload)
import "@hotwired/turbo-rails"

// Stimulus — lightweight JS framework
// Each "controller" adds behavior to HTML elements via data-controller attributes
import { Application } from "@hotwired/stimulus"

const application = Application.start()
window.Stimulus = application  // Expose globally for debugging in the browser console

// Import our Stimulus controllers
import CrawlFormController from "controllers/crawl_form_controller"
application.register("crawl-form",    CrawlFormController)

import CrawlHistoryController from "controllers/crawl_history_controller"
application.register("crawl-history", CrawlHistoryController)

// ActionCable consumer — opens the WebSocket for live crawl progress
import "consumer"

// Chartkick — renders the price trend chart. Chart.bundle must load before
// chartkick itself, since chartkick references the global it defines.
import "Chart.bundle"
import "chartkick"

// =============================================================================
// GLOBAL UTILITY FUNCTIONS
// =============================================================================

// Called when the user changes the sort dropdown in the results table
// Reloads the page with the new sort parameters in the URL
window.updateSort = function(value) {
  const [column, direction] = value.split("|")
  const url = new URL(window.location.href)
  url.searchParams.set("sort", column)
  url.searchParams.set("dir", direction)
  window.location.href = url.toString()
}

// POST to a URL and show a success/error toast — used by Settings page test buttons
window.testSetting = async function(url, buttonEl, successMsg, errorMsg) {
  const originalText = buttonEl.textContent
  buttonEl.textContent = "Testing..."
  buttonEl.disabled = true

  try {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(url, {
      method:  "POST",
      headers: {
        "X-CSRF-Token": token,
        "Accept":       "application/json"
      }
    })
    const data = await response.json()
    showToast(data.success ? (data.message || successMsg) : (data.message || errorMsg),
              data.success ? "success" : "error")
  } catch (err) {
    showToast("Request failed: " + err.message, "error")
  } finally {
    buttonEl.textContent = originalText
    buttonEl.disabled = false
  }
}

// Show a temporary toast notification in the top-right corner
window.showToast = function(message, type = "success") {
  // Remove any existing toast
  document.getElementById("sf-toast")?.remove()

  const toast = document.createElement("div")
  toast.id = "sf-toast"
  toast.style.cssText = "position:fixed;top:1rem;right:1rem;z-index:9999;padding:0.75rem 1rem;border-radius:0.375rem;font-size:0.875rem;font-weight:500;max-width:360px;"
  toast.style.background = type === "success" ? "#065f46" : "#7f1d1d"
  toast.style.color       = type === "success" ? "#d1fae5" : "#fecaca"
  toast.style.border      = `1px solid ${type === "success" ? "#059669" : "#b91c1c"}`
  toast.textContent = message
  document.body.appendChild(toast)
  setTimeout(() => toast.remove(), 5000)
}
