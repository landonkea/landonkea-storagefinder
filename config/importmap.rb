# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "consumer", to: "consumer.js"

# Chartkick — renders the price trend chart on the dashboard. Served from the
# gem's vendored assets (offline-friendly, no CDN — matters for a LAN app).
pin "Chart.bundle", to: "Chart.bundle.js"
pin "chartkick", to: "chartkick.js"
pin "@rails/actioncable", to: "@rails--actioncable.js" # @8.1.300
