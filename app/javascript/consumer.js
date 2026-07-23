// =============================================================================
// ACTION CABLE CONSUMER SETUP
// =============================================================================
// This file sets up the WebSocket connection that powers the live crawl
// progress feed on the dashboard.
//
// App.cable is referenced in the dashboard view's inline JavaScript.
// It opens a WebSocket connection to /cable on the server.
// =============================================================================

// `import { createConsumer } from "@rails/actioncable"` is a "named
// import" (curly braces): it pulls the specific `createConsumer` function
// out of Rails' ActionCable JS library. ActionCable is Rails' built-in
// system for WebSockets — a persistent two-way connection between browser
// and server, used here so the server can push live crawl-progress updates
// to the page without the browser having to keep asking ("polling") for them.
import { createConsumer } from "@rails/actioncable"

// Create the consumer and expose it globally as App.cable
// so the inline <script> in the dashboard view can access it
// `createConsumer("/cable")` opens (or prepares to open) a WebSocket
// connection to the "/cable" URL on this same server — that's the endpoint
// Rails' ActionCable server listens on by default. The returned `consumer`
// object is what's used elsewhere to subscribe to specific "channels"
// (topics), e.g. the CrawlProgressChannel referenced in
// app/views/dashboard/index.html.erb.
const consumer = createConsumer("/cable")

// Make it available globally — the dashboard view accesses it as App.cable
// `window.App = window.App || {}` first checks whether a global `App`
// object already exists on `window` (the browser's global scope); `||` is
// "or", so if `window.App` is falsy (undefined, since nothing has created
// it yet), the right side `{}` (a brand-new empty object) is assigned
// instead. This is a defensive pattern that avoids overwriting an existing
// `App` object if one were ever created elsewhere before this file runs.
window.App = window.App || {}
// Attaches the ActionCable consumer to `App.cable`, so any other script on
// the page — including plain inline <script> tags in ERB views, which
// don't go through JS imports — can reach it as the global `App.cable`.
window.App.cable = consumer

// `export default consumer` makes this module's main output the `consumer`
// object, so any other JS file that does `import consumer from "consumer"`
// (or, as in app/javascript/application.js, `import "consumer"` for its
// side effects only) can access it. This file is loaded once via
// `import "consumer"` in application.js purely to run the setup code above
// — nothing in this codebase currently imports the exported value itself,
// since everything reaches it through the global `App.cable` instead.
export default consumer
