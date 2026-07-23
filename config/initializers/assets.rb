# =============================================================================
# WHAT IS AN "INITIALIZER"? (read this once — it applies to every file in
# config/initializers/, not just this one)
# =============================================================================
# Rails automatically loads and RUNS every ".rb" file inside the
# config/initializers/ directory exactly once, when the application boots
# up — e.g. when you run `bin/rails server`, `bin/rails console`, start a
# background job worker, etc. This happens after Rails has finished loading
# all the gems (external libraries) listed in the Gemfile, but before your
# app starts handling any real web requests or console commands.
#
# The directory name itself is what makes this special: you do NOT need to
# list these files anywhere or manually `require` them. Rails scans
# config/initializers/ at boot and executes every *.rb file it finds there
# (alphabetically, by default). That's why this directory is the
# conventional place to put "run this setup/configuration code exactly once
# at startup" logic — e.g. configuring a gem, setting a global option,
# registering a background thread — as opposed to app/models or
# app/controllers, whose code runs per-request or per-object instead of
# once at boot.
#
# Because this code only runs at boot, changing anything in a file inside
# config/initializers/ has NO effect on an already-running server. You must
# stop and restart the Rails process for the change to take effect — unlike
# a controller or view file, which Rails typically reloads automatically
# between requests in development mode.
# =============================================================================

# A plain-English restatement of the "must restart" rule explained in the
# big comment block above: this line is itself just a comment (Ruby ignores
# anything after a `#` on a line — it's not executable code, only a note
# for human readers), left here by Rails' default file generator as a
# reminder specific to this file.
# Be sure to restart your server when you modify this file.

# This blank line has no effect on Ruby — it's purely a visual separator
# between the reminder comment above and the real configuration code below.

# Explains the purpose of the line immediately below: the "asset pipeline"
# is the part of Rails that bundles, compiles, and compresses your CSS,
# JavaScript, and image files into "assets" served to visitors' browsers.
# Browsers cache static files aggressively based on their URL. Rails
# appends a "fingerprint" (a short hash) to each asset's filename/URL so
# that when the underlying file's content changes, its URL changes too,
# forcing browsers to fetch the new version instead of reusing a stale
# cached one. This version string below is mixed into that fingerprint
# calculation.
# Version of your assets, change this if you want to expire all your assets.

# `Rails` is a Ruby module — Ruby's namespacing mechanism, essentially a
# named container that groups related classes/constants/methods together
# so their names don't collide with unrelated code. `.application` is a
# method call (no parentheses needed in Ruby when a method takes no
# arguments) that returns the single running instance of this app as an
# object. `.config` is that instance's configuration object, and
# `.assets.version` drills down further to one specific setting on it.
# `=` is Ruby's assignment operator: it sets `assets.version` to the string
# "1.0" (text data, delimited by double quotes). Changing this string to
# any other value (e.g. "1.1") is a manual way to force every cached asset
# to expire for all visitors at once, without touching any actual file
# content.
Rails.application.config.assets.version = "1.0"

# Another purely visual blank line, separating the asset-versioning setting
# above from the asset-load-path example below — no effect on execution.

# Explains the (currently inactive, commented-out) example line below: the
# "asset load path" is the list of directories Rails searches through when
# it needs to find a stylesheet, JavaScript file, or image referenced by an
# asset helper such as `image_tag`. By default this list already includes
# folders like app/assets/images, app/assets/stylesheets, etc. Some Ruby
# gems ship their own image/font files living outside your app's folders —
# adding such a gem's directory to this load path lets Rails' asset helpers
# find those files too.
# Add additional assets to the asset load path.

# This line begins with `#`, so Ruby treats the entire line as a comment —
# it is NOT executable code, just an example left by Rails' default
# generator showing the syntax you'd use if you needed this feature. If it
# WERE active (i.e. if you deleted the leading `#`): `paths` would be an
# Array (an ordered, mutable list) already containing the default asset
# directories; `<<` is Ruby's "append"/"shovel" operator, which pushes one
# more item onto the end of an array in place; `Emoji.images_path` would
# need to come from some third-party gem (e.g. the `gemoji` gem) that
# defines an `Emoji` module/class with an `images_path` method returning
# the folder where its bundled emoji image files live. Because this line
# stays commented out, StorageFinder does not currently pull in any such
# extra emoji image assets — nothing here needs to be fixed, it's simply
# unused example code left over from the Rails app template.
# Rails.application.config.assets.paths << Emoji.images_path
