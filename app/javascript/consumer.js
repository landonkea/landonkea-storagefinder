// =============================================================================
// ACTION CABLE CONSUMER SETUP
// =============================================================================
// This file sets up the WebSocket connection that powers the live crawl
// progress feed on the dashboard.
//
// App.cable is referenced in the dashboard view's inline JavaScript.
// It opens a WebSocket connection to /cable on the server.
// =============================================================================

import { createConsumer } from "@rails/actioncable"

// Create the consumer and expose it globally as App.cable
// so the inline <script> in the dashboard view can access it
const consumer = createConsumer("/cable")

// Make it available globally — the dashboard view accesses it as App.cable
window.App = window.App || {}
window.App.cable = consumer

export default consumer
