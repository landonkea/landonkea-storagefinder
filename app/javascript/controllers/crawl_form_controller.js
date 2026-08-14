// =============================================================================
// CRAWL FORM CONTROLLER
// =============================================================================
// Handles the "Run Crawl" form interactions:
//   - Toggle all company checkboxes at once
//   - Validate required fields before submit
// =============================================================================

// `import { Controller } from "@hotwired/stimulus"`, a "named import"
// (curly braces) that pulls the base `Controller` class out of the
// Stimulus library. Every Stimulus controller you write extends
// (inherits from) this class to get its core behavior (lifecycle
// callbacks, element/target lookups, etc.).
import { Controller } from "@hotwired/stimulus"

// `export default class extends Controller { ... }` does three things at
// once: `class extends Controller` defines a new JavaScript class that
// inherits everything from Stimulus's base `Controller` class (so it
// automatically knows how to find its own DOM element, wire up
// data-action bindings, etc.); the class here has no name of its own
// (an "anonymous class") because `export default` means "whatever this
// file's main/default export is", the importer gets to name it (see
// app/javascript/application.js, which imports this as
// `CrawlFormController`). This controller is attached to the HTML element
// that has `data-controller="crawl-form"`, see the <%= form_with ... %>
// call in app/views/dashboard/index.html.erb.
export default class extends Controller {

  // Called when the user clicks "Toggle all" next to company checkboxes
  // Methods defined directly inside a class body (no `function` keyword
  // needed) become that class's methods. Stimulus calls this one
  // automatically because of the HTML attribute
  // `data-action="click->crawl-form#toggleAllCompanies"` in the view,
  // that attribute means "on a click event, call the toggleAllCompanies
  // method on the crawl-form controller." `event` is the browser's
  // click-event object, passed in automatically.
  toggleAllCompanies(event) {
    // Since this button has `type="button"` it wouldn't normally submit
    // the form anyway, but `.preventDefault()` stops any default browser
    // behavior for this click just to be safe/explicit.
    event.preventDefault()

    // Find all company checkboxes in this form
    // `this.element` is provided by Stimulus's base Controller class, it's
    // the actual DOM element this controller is attached to (the element
    // with `data-controller="crawl-form"`). `.querySelectorAll(...)` finds
    // every descendant element matching the given CSS selector, here,
    // every <input> whose `name` attribute is exactly "companies[]" (the
    // square brackets in the name make Rails treat submitted values as an
    // array on the server side).
    // `:not(:disabled)` excludes stub-company checkboxes (see
    // app/views/dashboard/index.html.erb, any company whose parser isn't
    // implemented yet gets `disabled` set, none currently, see
    // CompanyRegistry::STUBBED_COMPANIES) from both the "are they all
    // checked?" calculation below and the toggle itself;
    // a disabled checkbox can't be usefully checked/unchecked by a user
    // anyway, and leaving it out of the count keeps "Toggle all" from
    // treating one permanently-unchecked stub as a reason to think
    // something's still unselected.
    const checkboxes = this.element.querySelectorAll("input[name='companies[]']:not(:disabled)")

    // If all are checked, uncheck all. If any are unchecked, check all.
    // `Array.from(checkboxes)` converts the NodeList returned by
    // querySelectorAll into a real JS Array, so array methods like
    // `.every()` are available. `.every(cb => cb.checked)` returns `true`
    // only if EVERY checkbox in the list is currently checked; `cb =>
    // cb.checked` is an arrow function shorthand for "given one checkbox
    // cb, return whether it's checked."
    const allChecked = Array.from(checkboxes).every(cb => cb.checked)

    // `.forEach(cb => { ... })` runs the given function once for every
    // checkbox in the (NodeList) collection, NodeLists support forEach
    // directly, no Array.from conversion needed for this method.
    checkboxes.forEach(cb => {
      cb.checked = !allChecked  // Flip the state
      // `!allChecked` is JS's "not" operator applied to allChecked: if
      // every box was already checked, this sets each box to `false`
      // (unchecked); if not all were checked, this sets each box to
      // `true` (checked), i.e. "select all" unless everything's already
      // selected, in which case "deselect all."
    })
    // `}` closes the `checkboxes.forEach(cb => { ... })` callback function.
  }
  // `}` closes the `toggleAllCompanies(event) { ... }` method.

  // Called when the form is submitted, do a quick client-side check
  // before letting the request go to the server
  // This method is wired up the same way, via a data-action attribute (not
  // shown directly in the excerpt read, but implied by the form's
  // controller wiring) for the form's "submit" event.
  submit(event) {
    // Looks for the text input holding the city/ZIP search value, scoped
    // to inputs inside this controller's element (the form).
    const cityField = this.element.querySelector("input[name='search_city']")

    // Guards against two problems at once: `!cityField` covers "the field
    // doesn't exist on the page at all" (defensive coding); `||` (or)
    // means either condition being true triggers this block.
    // `.trim()` removes leading/trailing whitespace, so a field containing
    // only spaces is treated the same as an empty field.
    if (!cityField || cityField.value.trim() === "") {
      event.preventDefault()  // Stop the form from submitting
      // `preventDefault()` here is essential, it stops the browser's
      // normal form-submission behavior (sending the request to the
      // server), because we want to block an invalid submission entirely.
      alert("Please enter a city name or ZIP code.")
      // `alert(...)` shows a blocking browser popup with the given
      // message, a simple, no-dependencies way to warn the user.
      // `cityField?.focus()`, optional chaining (`?.`) guards against
      // cityField being null (from the `!cityField` case above); `.focus()`
      // moves the browser's text cursor into that field so the user can
      // immediately start typing a correction.
      cityField?.focus()
      // `return` exits this method immediately, none of the code below
      // (the company-checkbox check, disabling the submit button) runs
      // once we've already decided to block this submission.
      return
    }
    // `}` closes the `if (!cityField || ...) { ... }` block above.

    // Looks for any company checkboxes that ARE currently checked (note
    // the `:checked` CSS pseudo-selector added to the same selector used
    // in toggleAllCompanies above), at least one company must be selected
    // to run a crawl.
    const checkboxes = this.element.querySelectorAll("input[name='companies[]']:checked")
    if (checkboxes.length === 0) {
      // `.length` on a NodeList is how many elements matched; zero means
      // no company checkboxes are checked.
      event.preventDefault()
      alert("Please select at least one company to crawl.")
      return
      // Exits early again, same reasoning as above, an invalid form
      // shouldn't proceed to disable the submit button either.
    }
    // `}` closes the `if (checkboxes.length === 0) { ... }` block above.

    // Disable the submit button so the user can't double-click and start two crawls
    // Only reached if both validations above passed (the function didn't
    // already `return`). Looks for the actual <button type="submit"> to
    // give feedback and prevent duplicate submissions.
    const submitBtn = this.element.querySelector("button[type='submit']")
    // Guard in case the button isn't found for some reason, avoids a
    // "cannot set property on null" crash.
    if (submitBtn) {
      // Disabling the button visually greys it out and makes it
      // unclickable, so a user who double-clicks (or clicks again while
      // waiting) can't accidentally start a second crawl for the same form.
      submitBtn.disabled = true
      // Changes the button's visible label to reassure the user something
      // is happening.
      submitBtn.textContent = "Starting crawl..."
    }
    // `}` closes the `if (submitBtn) { ... }` block above.
  }
  // `}` closes the `submit(event) { ... }` method.
}
// `}` closes the `export default class extends Controller { ... }` class
// definition that started at the top of the file.
