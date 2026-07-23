// `import { Controller } from "@hotwired/stimulus"` — named import of
// Stimulus's base Controller class. Every Stimulus controller extends
// (inherits from) this class.
import { Controller } from "@hotwired/stimulus"

// `export default class extends Controller { ... }` — an anonymous class
// extending Stimulus's Controller, exported as this file's default export.
// This is the standard "starter" controller generated automatically by
// Rails' `bin/rails generate stimulus hello` command (or created by the
// Stimulus/importmap installer) — a minimal example meant to be replaced
// or deleted once real controllers exist.
export default class extends Controller {
  // `connect()` is one of Stimulus's built-in "lifecycle callback" method
  // names — Stimulus automatically calls `connect()` the moment an element
  // with a matching `data-controller="hello"` attribute appears in the
  // page and this controller is attached to it. You don't call `connect()`
  // yourself; Stimulus calls it for you.
  connect() {
    // `this.element` is the actual DOM element this controller is attached
    // to (provided automatically by the base Controller class).
    // `.textContent = "..."` replaces all of that element's visible text
    // with "Hello World!" — a simple visible proof that the controller
    // connected successfully.
    this.element.textContent = "Hello World!"
  }
  // `}` closes the `connect() { ... }` method.
}
// `}` closes the `export default class extends Controller { ... }` class
// definition that started above.

// FLAG (not fixed — comments-only pass): this controller is never
// registered in app/javascript/application.js (only "crawl-form" and
// "crawl-history" are registered there), and no HTML anywhere in
// app/views uses `data-controller="hello"` (confirmed by searching the
// repo). This looks like leftover boilerplate from the Stimulus
// installer/generator that was never wired up or removed — it currently
// has no effect on the running app.
