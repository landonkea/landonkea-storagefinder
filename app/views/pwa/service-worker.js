// =============================================================================
// SERVICE WORKER (currently a stub / template — no active code)
// =============================================================================
// A "service worker" is a special JavaScript file that a browser can run in
// the background for a site, separate from any particular open tab/page —
// it can keep running (within limits) even after the user closes the tab.
// It's the piece of a "Progressive Web App" (see app/views/pwa/
// manifest.json.erb for that term explained) responsible for things a
// normal page script can't do: intercepting network requests to support
// offline use, and receiving "push" notifications from a server even when
// no tab for this site is open.
//
// This file lives at app/views/pwa/service-worker.js (note: plain .js, NOT
// .js.erb — no Ruby templating here) because Rails' built-in
// Rails::PwaController serves it dynamically, the same way it serves
// manifest.json.erb. Every line below this banner is a JavaScript comment
// (using `//`), meaning NONE of it currently runs — this file is entirely
// inert right now. It ships this way from Rails' own default app generator,
// as a ready-to-uncomment starting point for a developer who wants to add
// Web Push notification support later.
//
// FLAG (see end-of-task report): same issue noted in manifest.json.erb —
// config/routes.rb has no route for `rails/pwa#service_worker`, and no
// page registers a service worker via JavaScript
// (`navigator.serviceWorker.register(...)`) either. Even if the code below
// were uncommented, nothing currently causes a browser to install or run
// this file. Not fixed here — comments-only pass.
//
// Below this point, every "//" line (including every bare "//" with no
// text after it) is part of the ORIGINAL file, character-for-character —
// a developer's commented-out example of a working push-notification
// service worker, left as a template. This pass adds explanatory prose
// comments immediately above each original line without changing,
// removing, or reordering a single one of them.

// Add a service worker for processing Web Push notifications:
//
// This is an original blank "//" separator line from the source file —
// visual spacing within the commented-out example, nothing to explain.
//
// `self` inside a service worker file refers to the service worker's own
// global scope (service workers don't have a `window` object the way
// normal page scripts do — `self` is the equivalent "this is me"
// reference here). `.addEventListener("push", async (event) => { ... })`
// would register a function to run every time the browser receives a push
// notification meant for this site — `"push"` names WHICH kind of event
// to listen for, and the second argument is the function to run when it
// happens, written as an "arrow function" (JavaScript's compact function
// syntax: `(params) => { body }`). The `async` keyword marks the function
// as allowed to use `await` inside it (see the next line) to pause until
// an asynchronous operation completes.
// self.addEventListener("push", async (event) => {
//   `event.data.json()` reads the push message's payload and parses it as
//   JSON (see manifest.json.erb for what JSON is); it returns a Promise (a
//   placeholder for a value not ready yet), so `await` pauses this
//   function until the real parsed object is available. `const { title,
//   options } = ...` is JavaScript "destructuring": it pulls the `title`
//   and `options` fields out of that parsed object directly into two
//   same-named local variables in one step.
//   const { title, options } = await event.data.json()
//   `event.waitUntil(...)` tells the browser "don't consider this push
//   event finished until the thing inside this call finishes" — needed
//   because the browser could otherwise suspend the service worker before
//   the notification actually finishes displaying.
//   `self.registration.showNotification(title, options)` is the actual
//   browser API call that pops up an OS-level notification using the
//   `title` and `options` (e.g. icon, body text) extracted above.
//   event.waitUntil(self.registration.showNotification(title, options))
// `})` closes the arrow function passed to addEventListener, and then the
// addEventListener(...) call itself, both on this one line.
// })
//
// This is an original blank "//" separator line, dividing the "push"
// handler above from the "notificationclick" handler below.
//
// This second listener would run whenever the user actually CLICKS a
// notification shown by the code above, rather than when it first
// arrives. `function(event) { ... }` here is JavaScript's older,
// non-arrow way of writing a function — functionally similar to the arrow
// function used above, just different syntax (this file mixes both
// styles, which is fine in JavaScript but a little inconsistent).
// self.addEventListener("notificationclick", function(event) {
//   `event.notification.close()` dismisses/removes the notification from
//   the OS notification tray, now that the user has clicked it.
//   event.notification.close()
//   `event.waitUntil(...)` again tells the browser to keep this service
//   worker alive until the Promise chain inside finishes. Unlike the
//   single-line use above, here the call spans several lines — the
//   opening parenthesis on this line isn't closed until several lines down.
//   event.waitUntil(
//     `clients.matchAll({ type: "window" })` asks the browser for every
//     currently-open browser tab/window controlled by this service worker
//     (`{ type: "window" }` filters to window/tab clients specifically).
//     This itself returns a Promise, so `.then((clientList) => { ... })`
//     supplies the function to run once that list is ready, with
//     `clientList` being the resulting array of matching tabs/windows.
//     clients.matchAll({ type: "window" }).then((clientList) => {
//       `for (let i = 0; i < clientList.length; i++) { ... }` is a
//       classic counting for-loop: `let i = 0` starts a counter at zero,
//       `i < clientList.length` is checked before each pass (the loop
//       stops once it's false), and `i++` increases the counter by one
//       after each pass — together, this visits every index in
//       clientList from first to last.
//       for (let i = 0; i < clientList.length; i++) {
//         `let client = clientList[i]` reads the one tab/window object at
//         the current loop position `i` into a local variable for the
//         lines below to use.
//         let client = clientList[i]
//         `new URL(client.url)` parses that tab's current web address
//         into a structured URL object; `.pathname` then extracts just the
//         path portion (e.g. "/dashboard" out of a full address like
//         "https://example.com/dashboard?x=1"). The parentheses around
//         `(new URL(client.url))` just make the following `.pathname`
//         access read unambiguously.
//         let clientPath = (new URL(client.url)).pathname
//
//         This is an original blank "//" separator line, dividing the
//         URL-parsing step above from the matching/focusing check below.
//
//         `if (clientPath == event.notification.data.path && "focus" in
//         client) { ... }` checks two things with `&&` ("and" — both
//         sides must be true): (1) does this tab's current path match a
//         path that was attached to the notification's own data when it
//         was created (so clicking the notification can jump back to the
//         SPECIFIC page it was about), and (2) does this `client` object
//         actually support a `.focus()` method (`"focus" in client`
//         checks whether that property exists on the object — not every
//         client type does).
//         if (clientPath == event.notification.data.path && "focus" in client) {
//           `return client.focus()` brings that already-open tab to the
//           front for the user; `return` here exits the surrounding
//           function early (from inside the for-loop) since a matching
//           tab was found — no need to keep checking the rest of
//           clientList.
//           return client.focus()
//         `}` closes the `if (...)` block opened just above.
//         }
//       `}` closes the `for (...)` loop opened above — every open tab has
//       now been checked for a matching path.
//       }
//
//       This is an original blank "//" separator line, dividing the loop
//       above from the fallback case below (reached only if no open tab
//       matched).
//
//       `if (clients.openWindow) { ... }` checks that the browser
//       actually supports the `openWindow` API before trying to use it —
//       a basic feature-detection safety check, since support can vary.
//       if (clients.openWindow) {
//         If no already-open tab matched above, this opens a BRAND NEW
//         browser tab/window at the path stored on the notification,
//         instead of focusing an existing one.
//         return clients.openWindow(event.notification.data.path)
//       `}` closes the `if (clients.openWindow)` block opened above.
//       }
//     `})` closes the function passed to `.then(...)`, and then the
//     `.then(...)` call itself, both on this one line.
//     })
//   `)` closes the `event.waitUntil(...)` call opened several lines above
//   (the one wrapping the whole `clients.matchAll(...).then(...)` chain).
//   )
// `})` closes the function passed to addEventListener, and then the
// addEventListener(...) call itself, both on this one line — this is the
// very last line of the commented-out example.
// })
