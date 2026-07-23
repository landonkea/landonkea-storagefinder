# A reminder that, like every file in config/initializers/, this one only
# takes effect at application boot — editing it has no effect on an
# already-running server until it is stopped and restarted. (See
# config/initializers/assets.rb for a full explanation of what an
# "initializer" is and why Rails auto-loads everything in this directory.)
# Be sure to restart your server when you modify this file.

# Blank line — purely visual spacing, has no effect on Ruby.

# A multi-line comment (left by Rails' generator) explaining what
# "inflection rules" are and giving a worked example of the syntax, entirely
# as an inactive block (every line below starts with `#`, so none of it
# executes). "Inflection" here means turning a word between its singular and
# plural forms (e.g. "person" <-> "people", "fish" <-> "fish") — Rails uses
# these rules throughout, e.g. to guess a database table name ("people")
# from a model class name (`Person`), or to build a human-readable label
# from a class/column name.
# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# If uncommented, `ActiveSupport::Inflector.inflections(:en) do |inflect|
# ... end` would open a block for registering custom inflection rules
# specifically for the `:en` (English) locale — `:en` here is a Ruby Symbol
# naming the locale, matching the `en:` key used in config/locales/en.yml.
# `|inflect|` names the block's one argument: an object with methods for
# registering each kind of rule, used on the example lines below it.
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   `inflect.plural /^(ox)$/i, "\\1en"` would register a REGEX-based plural
#   rule: any word matching the pattern `/^(ox)$/i` (exactly "ox", case-
#   insensitively — the `i` flag after the closing `/` means "ignore case";
#   `^` and `$` anchor the match to the whole word start/end; parentheses
#   `( )` capture the matched text for reuse) gets pluralized by the
#   replacement string `"\\1en"`, where `\\1` refers back to whatever text
#   the `(ox)` group captured — producing "oxen".
#   inflect.plural /^(ox)$/i, "\\1en"
#   The reverse rule: singularizing anything matching `/^(ox)en/i` (i.e.
#   "oxen", case-insensitively) back down to just the captured `(ox)` part,
#   i.e. "ox".
#   inflect.singular /^(ox)en/i, "\\1"
#   `inflect.irregular "person", "people"` registers a pair of words that
#   don't follow any general pluralization PATTERN at all and must simply be
#   listed explicitly — "person" becomes "people" (not "persons").
#   inflect.irregular "person", "people"
#   `inflect.uncountable %w( fish sheep )` marks the listed words as having
#   NO distinct plural form at all — "fish" stays "fish" whether one or many
#   are meant. `%w( fish sheep )` is Ruby's "word array" shorthand (see
#   config/application.rb for a fuller explanation) building the Array
#   `["fish", "sheep"]`.
#   inflect.uncountable %w( fish sheep )
# end
# `end` (in this commented-out example) would close the
# `ActiveSupport::Inflector.inflections(:en) do |inflect|` block opened
# above it.

# Blank line — purely visual spacing, has no effect on Ruby.

# A second inactive example block, demonstrating a DIFFERENT kind of
# inflection rule than the ones above: this comment notes these rules exist
# and are supported, but are not registered by Rails automatically the way
# the ones in the first example block are (hence "not enabled by default").
# These inflection rules are supported but not enabled by default:
# Same block-opening syntax as the first example above — see that block's
# comments for what `ActiveSupport::Inflector.inflections(:en) do |inflect|`
# means.
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   `inflect.acronym "RESTful"` would register "RESTful" as a known
#   ACRONYM/special-cased word — this affects Rails' `camelize`/`humanize`-
#   style string-transformation helpers so that, for example, a name like
#   "restful_controller" gets correctly turned into "RESTfulController"
#   (preserving the acronym's own internal capitalization) instead of the
#   default "RestfulController".
#   inflect.acronym "RESTful"
# end
# `end` (in this second commented-out example) would close the block opened
# just above it.

# Nothing in this file is currently active — StorageFinder does not
# register any custom inflection rules of its own; both blocks above remain
# exactly as Rails' project generator left them, as inactive documentation/
# examples only.
