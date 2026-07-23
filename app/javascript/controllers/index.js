// =============================================================================
// STIMULUS CONTROLLERS INDEX
// =============================================================================
// Stimulus auto-discovers controllers from this folder.
// Each controller filename must end in _controller.js
// and the class exported must extend Controller.
//
// Currently registered controllers:
//   crawl-form     → crawl_form_controller.js    (form validation + company toggle)
//   crawl-history  → crawl_history_controller.js (history panel select-all + bulk delete)
//
// The cancel-crawl button works via a plain Rails button_to — no Stimulus
// controller needed for it.
// =============================================================================

// `import { application } from "./application"` — a "named import" (curly
// braces) that pulls the `application` value out of the sibling file
// app/javascript/controllers/application.js (the `"./application"` path
// means "the file named application.js in this same folder"). That file
// exports its own separate Stimulus `Application.start()` instance under
// the name `application`.
import { application } from "./application"

// FLAG (not fixed — comments-only pass): despite this file's own header
// comment saying "Stimulus auto-discovers controllers from this folder,"
// this file does not actually call any auto-loading function (e.g.
// Stimulus's `eagerLoadControllersFrom`/`lazyLoadControllersFrom` helpers,
// which is the real mechanism that would import and register every
// *_controller.js file automatically) — searching the repo found no such
// call anywhere. This file only imports `application` from
// ./application.js and does nothing else with it; it doesn't import or
// register crawl_form_controller.js or crawl_history_controller.js itself.
// Separately, nothing else in the codebase imports this index.js file at
// all (confirmed by searching the repo) — the app's real entry point,
// app/javascript/application.js, bypasses this file entirely: it creates
// its OWN independent `Application.start()` instance and manually
// registers CrawlFormController and CrawlHistoryController by importing
// them directly. So both this file and ./application.js appear to be
// unused leftover scaffolding from Rails' default Stimulus/importmap
// installer, and the header comment above (predating this note) describes
// a controller auto-loading setup that isn't actually happening in this
// app.
