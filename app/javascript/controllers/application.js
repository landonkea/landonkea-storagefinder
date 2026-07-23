// `import { Application } from "@hotwired/stimulus"` — a "named import"
// (curly braces) that pulls the `Application` class out of the Stimulus
// library. Stimulus is Rails' lightweight JavaScript framework: instead of
// a big single-page-app framework, it attaches small "controller" classes
// to plain HTML elements marked with a `data-controller="name"` attribute,
// adding just enough interactivity to otherwise server-rendered pages.
import { Application } from "@hotwired/stimulus"

// `Application.start()` creates a new Stimulus application instance — the
// object that scans the page's HTML for `data-controller` attributes and
// wires up matching controller classes to those elements. `const` means
// this local variable can't be reassigned later in this file.
const application = Application.start()

// Configure Stimulus development experience
// `application.debug = false` turns off Stimulus's verbose console logging
// (which would otherwise print every controller connect/disconnect event
// and action dispatch to the browser console) — useful while debugging
// Stimulus itself, but noisy for normal development, so it's disabled here.
application.debug = false
// Exposes this Stimulus application instance globally as `window.Stimulus`
// so it can be inspected from the browser's developer console.
window.Stimulus   = application

// `export { application }` is a "named export" — it makes the local
// `application` variable available to any other file that writes
// `import { application } from "./application"`. This is different from
// `export default`, which exports a single unnamed "main" value per file;
// with a named export, the importer must use the exact name `application`
// (wrapped in curly braces) to receive it.
export { application }

// FLAG (not fixed — comments-only pass): this file creates its OWN
// separate `Application.start()` instance, completely independent from the
// one created in app/javascript/application.js (the app's actual JS entry
// point, which Rails loads first). The real controller registration for
// this app (crawl-form, crawl-history) happens directly in
// app/javascript/application.js against ITS OWN `application` constant —
// not this one. Nothing in the codebase imports `{ application }` from
// this file except app/javascript/controllers/index.js, and nothing
// imports index.js either (confirmed by searching the repo). That means
// this file (and index.js) appear to be unused leftover scaffolding from
// Rails' default Stimulus generator setup, never actually executed by the
// browser, and `window.Stimulus` here would only ever matter if this file
// were loaded — which it currently isn't.
