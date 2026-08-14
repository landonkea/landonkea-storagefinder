# A reminder that, like every file in config/initializers/, this one only
# takes effect at application boot, editing it has no effect on an
# already-running server until it is stopped and restarted. (See
# config/initializers/assets.rb for a full explanation of what an
# "initializer" is and why Rails auto-loads everything in this directory.)

# Explains the purpose of the line below: Playwright is a third-party
# browser-automation library (it drives a real, headless, i.e. invisible/
# no on-screen window, web browser under program control), used elsewhere
# in this app by CrawlJob (a background job, see config/application.rb's
# BACKGROUND JOBS section for how jobs run) and ReconService (a plain Ruby
# class under app/services/) to load and scrape pages from storage-company
# websites that require actual JavaScript execution to render their prices.
# Load the Playwright gem so it's available in CrawlJob and ReconService
# `require "playwright"` loads the "playwright" gem (already listed in this
# app's Gemfile) at boot time, making its top-level `Playwright` module/
# classes available everywhere in the app afterward, without CrawlJob or
# ReconService needing to `require` it themselves each time they're loaded.
require "playwright"
