// =============================================================================
// JAVASCRIPT ENTRY POINT
// =============================================================================
// Rails loads this file first via the importmap.
// It sets up Turbo, Stimulus, ActionCable, and global utilities.
// =============================================================================

// `import "some-name"` pulls in a JavaScript module before this file's own
// code runs. "some-name" isn't a raw file path — Rails' importmap system
// (configured in config/importmap.rb) maps short names like
// "@hotwired/turbo-rails" to the actual vendored/downloaded JS file the
// browser should fetch. This is how this app loads JS libraries without a
// bundler like Webpack.
//
// Turbo — makes page navigation fast by replacing only changed content
// (page transitions feel instant without a full reload)
import "@hotwired/turbo-rails"

// This import uses `{ Application }` (curly braces) instead of a plain name.
// That's a "named import" — it pulls out one specific exported value
// (here, a class called `Application`) from the "@hotwired/stimulus"
// module, rather than importing the whole module as one thing.
//
// Stimulus — lightweight JS framework
// Each "controller" adds behavior to HTML elements via data-controller attributes
import { Application } from "@hotwired/stimulus"

// `Application.start()` is a class method (called on the class itself, not
// on an instance of it) that creates and initializes a new Stimulus
// "application" — the central object that watches the page's HTML for
// data-controller attributes and connects registered controller classes to
// matching elements. `const` declares a constant: `application` can't be
// reassigned to a different value later in this file.
const application = Application.start()
// Attaching to `window` (the global browser object) makes `application`
// reachable from the browser's developer console as `Stimulus`, e.g. typing
// `Stimulus.controllers` while debugging. The trailing `//` comment is an
// inline comment — everything after `//` on this line is ignored by
// JavaScript and is just a note for humans.
window.Stimulus = application  // Expose globally for debugging in the browser console

// Import our Stimulus controllers
// `import CrawlFormController from "..."` (no curly braces) is a "default
// import" — it grabs whatever that module exported with `export default`
// (see crawl_form_controller.js, which does exactly that) and names it
// CrawlFormController here. The path "controllers/crawl_form_controller"
// resolves via the `pin_all_from "app/javascript/controllers", under:
// "controllers"` line in config/importmap.rb, which pins every file in
// that folder under the "controllers/" namespace automatically.
import CrawlFormController from "controllers/crawl_form_controller"
// `application.register(name, ControllerClass)` tells Stimulus: "whenever
// you see an element with data-controller='crawl-form' in the HTML, attach
// an instance of CrawlFormController to it." The extra spaces before
// CrawlFormController are just manual alignment with the line below and
// don't affect how the code runs.
application.register("crawl-form",    CrawlFormController)

import CrawlHistoryController from "controllers/crawl_history_controller"
application.register("crawl-history", CrawlHistoryController)

// Facility map — renders the Leaflet map of nearby facilities on the
// dashboard (see app/javascript/controllers/facility_map_controller.js and
// the "leaflet" pin in config/importmap.rb).
import FacilityMapController from "controllers/facility_map_controller"
application.register("facility-map", FacilityMapController)

// This import has no `import X from` or `import { X } from` part at all —
// it's a "side-effect only" import, meaning we don't need any value out of
// the "consumer" module, we just want its top-level code (in consumer.js)
// to run once, since that's what opens the ActionCable WebSocket.
//
// ActionCable consumer — opens the WebSocket for live crawl progress
import "consumer"

// Chartkick — renders the price trend chart. Chart.bundle must load before
// chartkick itself, since chartkick references the global it defines.
// Import order matters here: because these are both side-effect imports
// that define global variables (not proper ES modules with clean exports),
// "Chart.bundle" MUST run first so its global exists by the time
// "chartkick"'s own top-level code looks for it.
import "Chart.bundle"
import "chartkick"

// =============================================================================
// GLOBAL UTILITY FUNCTIONS
// =============================================================================

// Called when the user changes the sort dropdown in the results table
// Reloads the page with the new sort parameters in the URL
// Assigning a function to `window.updateSort` (rather than using Stimulus)
// makes this function callable directly from plain HTML, e.g. an inline
// `onchange="updateSort(this.value)"` attribute in a view — see
// app/views/dashboard/index.html.erb. `function(value) { ... }` is an
// old-style (non-arrow) function expression; `value` is its one parameter.
window.updateSort = function(value) {
  // The dropdown's value looks like "monthly_price|asc" — a column name
  // and a sort direction joined by a pipe character. `.split("|")` breaks
  // the string into an array at each "|", giving ["monthly_price", "asc"].
  // The `const [column, direction] = ...` syntax on the left is "array
  // destructuring" — it unpacks the first array element into `column` and
  // the second into `direction` in one step, instead of writing
  // `const column = parts[0]; const direction = parts[1]`.
  const [column, direction] = value.split("|")
  // `new URL(...)` parses the current page's full address (protocol, host,
  // path, and any existing query string) into a URL object we can modify
  // piece by piece, rather than manually string-splicing "?sort=...".
  const url = new URL(window.location.href)
  // `.searchParams` is the URL object's query-string handler. `.set(key,
  // value)` adds the "sort" parameter if missing, or overwrites it if a
  // "sort" parameter already exists in the URL.
  url.searchParams.set("sort", column)
  // Same idea for the "dir" (direction) parameter.
  url.searchParams.set("dir", direction)
  // Setting `window.location.href` to a new address navigates the browser
  // there — this is a full-page navigation (or a Turbo-accelerated one,
  // since Turbo is loaded above) to the same page but with new sort
  // parameters in the URL, causing Rails to re-render results in that order.
  window.location.href = url.toString()
}
// `}` closes the `window.updateSort = function(value) { ... }` function body
// opened above.

// POST to a URL and show a success/error toast — used by Settings page test buttons
// `async function(...)` marks this function as asynchronous, which lets us
// use the `await` keyword inside it (see below) to pause execution until a
// network request finishes, without blocking the rest of the page.
window.testSetting = async function(url, buttonEl, successMsg, errorMsg) {
  // Save the button's current label so it can be restored later, no matter
  // how this function finishes (success, error, or exception).
  const originalText = buttonEl.textContent
  // Give the user instant feedback that their click registered.
  buttonEl.textContent = "Testing..."
  // Prevent the user from clicking the button again while the request is
  // in flight (which could fire duplicate requests).
  buttonEl.disabled = true

  // `try { ... } catch (err) { ... } finally { ... }` is JS's error-handling
  // structure: code in `try` runs normally; if it throws an exception,
  // execution jumps to `catch`; the `finally` block always runs last,
  // whether or not an error happened — used here to guarantee the button
  // gets re-enabled either way.
  try {
    // Rails embeds a CSRF (Cross-Site Request Forgery) protection token in
    // a <meta name="csrf-token"> tag in the page's <head>. `?.` is
    // "optional chaining" — if `document.querySelector(...)` finds no
    // matching element (returns null), `?.content` short-circuits to
    // `undefined` instead of throwing a "cannot read property of null"
    // error. `.content` reads that meta tag's value attribute.
    const token = document.querySelector("meta[name='csrf-token']")?.content
    // `fetch(url, { ... })` sends an HTTP request to `url` using the
    // browser's built-in networking API. `await` pauses this function
    // (without freezing the whole page) until the server responds.
    const response = await fetch(url, {
      // `method: "POST"` — this is a POST request, the standard HTTP verb
      // for triggering an action/change on the server (vs. GET, for just
      // reading data).
      method:  "POST",
      // `headers` are extra metadata sent with the request.
      headers: {
        // Sends Rails' CSRF token back to the server so it can verify this
        // request really came from this page (not a malicious external site).
        "X-CSRF-Token": token,
        // Tells the server "please respond with JSON," so Rails' controller
        // knows to render a JSON response instead of HTML.
        "Accept":       "application/json"
      }
    })
    // Parses the response body as JSON and waits for that parsing to
    // finish (`.json()` itself returns a promise, hence the second `await`).
    const data = await response.json()
    // `showToast(message, type)` is defined further down this same file.
    // The `?:` here is JS's ternary (conditional) operator: `condition ?
    // valueIfTrue : valueIfFalse`. This picks the toast's message: if the
    // server says success, prefer its own message but fall back to
    // `successMsg`; otherwise prefer its message but fall back to
    // `errorMsg`. `||` means "use the left side if it's truthy, otherwise
    // use the right side" — so an empty/missing `data.message` falls
    // through to the fallback text.
    showToast(data.success ? (data.message || successMsg) : (data.message || errorMsg),
              data.success ? "success" : "error")
  } catch (err) {
    // If `fetch` itself failed (e.g. no network connection) or anything
    // above threw, show a generic failure toast including the raw error
    // text (`err.message`) so it's easier to debug.
    showToast("Request failed: " + err.message, "error")
  } finally {
    // Runs no matter what happened above — always restore the button to
    // its original clickable state.
    buttonEl.textContent = originalText
    buttonEl.disabled = false
  }
  // `}` closes the `finally` block opened above.
}
// `}` closes the `window.testSetting = async function(...) { ... }` function
// body opened above.

// Show a temporary toast notification in the top-right corner
window.showToast = function(message, type = "success") {
  // `type = "success"` in the parameter list is a "default parameter" — if
  // the caller doesn't pass a second argument, `type` defaults to the
  // string "success" instead of being `undefined`.
  //
  // Remove any existing toast
  // `document.getElementById("sf-toast")` looks for an element with
  // id="sf-toast" already on the page (a previous toast that hasn't been
  // cleaned up yet). `?.remove()` — optional chaining again — calls
  // `.remove()` (deletes the element from the page) only if that element
  // was actually found; otherwise this line does nothing.
  document.getElementById("sf-toast")?.remove()

  // `document.createElement("div")` builds a new, empty <div> HTML element
  // in memory — it isn't visible on the page until it's attached below.
  const toast = document.createElement("div")
  // Gives the new element the id "sf-toast" so future calls to this
  // function can find and remove it (see the line above).
  toast.id = "sf-toast"
  // `.style.cssText` sets a whole block of inline CSS at once, as a single
  // semicolon-separated string, instead of setting each style property
  // individually. This positions the toast fixed in the top-right corner
  // of the viewport, above other content (`z-index:9999`), with padding,
  // rounded corners, and a max width so long messages wrap.
  toast.style.cssText = "position:fixed;top:1rem;right:1rem;z-index:9999;padding:0.75rem 1rem;border-radius:0.375rem;font-size:0.875rem;font-weight:500;max-width:360px;"
  // Sets the background color based on toast type: dark green for success,
  // dark red for error. Again using the `?:` ternary operator.
  toast.style.background = type === "success" ? "#065f46" : "#7f1d1d"
  // Sets the text color to a lighter tint of the matching color, so text
  // is readable against the dark background above.
  toast.style.color       = type === "success" ? "#d1fae5" : "#fecaca"
  // Sets a 1px border in a slightly brighter shade of the same color
  // family. The backtick string here (`` `...` ``) is a JS "template
  // literal" — it lets `${...}` embed a JS expression's value directly
  // inside the string, so the border color is computed the same way as
  // above but interpolated into the "1px solid COLOR" text.
  toast.style.border      = `1px solid ${type === "success" ? "#059669" : "#b91c1c"}`
  // Sets the visible text inside the toast to whatever message was passed in.
  toast.textContent = message
  // Actually attaches the toast element to the page by adding it as the
  // last child of <body> — only now does it become visible on screen.
  document.body.appendChild(toast)
  // `setTimeout(fn, 5000)` schedules `fn` to run once, after 5000
  // milliseconds (5 seconds). `() => toast.remove()` is an arrow function
  // — a shorthand way to write a small function, here removing the toast
  // from the page so it auto-dismisses after 5 seconds.
  setTimeout(() => toast.remove(), 5000)
}
// `}` closes the `window.showToast = function(message, type = "success") { ... }`
// function body opened above.
