# =============================================================================
# ALERT MESSAGE BUILDER
# =============================================================================
# Builds the message content for alert notifications in different formats.
#
# Lives in its own file (not alongside AlertDeliveryService, even though this
# directory is Zeitwerk-collapsed, see the "storagefinder.autoload_collapse"
# initializer in config/application.rb) because Zeitwerk only autoloads one
# constant per file, matched to the filename. AlertCheckerJob#send_alerts
# references AlertMessageBuilder before AlertDeliveryService, so if this
# class isn't independently autoloadable, that reference raises
# "uninitialized constant AlertMessageBuilder" the first time it runs in a
# fresh process, silently caught by AlertCheckerJob's own rescue, so no
# alert ever gets sent and nothing visibly errors.
# =============================================================================

# This is a "service object", a plain Ruby class that isn't a database
# model or a web controller, used to hold one focused piece of logic (here:
# turning "a triggered alert rule + the units that triggered it" into
# actual message text in several formats). See
# app/services/company_registry.rb for a fuller explanation of what a
# service object is and why apps use them.
#
# "Zeitwerk" (mentioned in the header comment above) is Rails' code-loading
# system, it automatically finds and loads Ruby files based on their file
# path and file name, without needing explicit `require` statements
# scattered everywhere. That's why this file doesn't need a `require` line
# to be usable elsewhere in the app: naming this file
# `alert_message_builder.rb` and defining `class AlertMessageBuilder` inside
# it is enough for Zeitwerk to find and load it automatically the first time
# something references the AlertMessageBuilder constant.
class AlertMessageBuilder
  # `def self.build(...)` is a "class method" (called directly on the class
  # itself, e.g. `AlertMessageBuilder.build(rule, units)`, without needing
  # to create an instance first). This one exists purely as a convenience
  # shortcut: it creates a real instance via `.new` and immediately calls
  # `.build` on it, so callers don't have to write
  # `AlertMessageBuilder.new(rule, units).build` themselves every time.
  def self.build(rule, triggered_units)
    new(rule, triggered_units).build
  end
  # `end` closes the `def self.build` class method definition above.

  # `initialize` is Ruby's special constructor method name, it
  # automatically runs whenever `.new` is called on this class, and
  # whatever arguments are passed to `.new` are passed straight through to
  # `initialize`.
  def initialize(rule, triggered_units)
    # `@rule` and `@triggered_units` are INSTANCE VARIABLES (the `@` prefix
    # is what marks a variable as belonging to this specific object rather
    # than being a local, throwaway variable). Storing the constructor's
    # arguments in instance variables here is what lets every other method
    # in this class (build, build_subject, build_text_body, etc.) access
    # `@rule` and `@triggered_units` later, without having to pass them
    # around as method arguments every time.
    @rule            = rule
    @triggered_units = triggered_units
  end
  # `end` closes the `def initialize` method definition above.

  # `build` is the main public instance method, called as
  # `some_builder_instance.build` (which is exactly what `self.build`
  # above does for you). It assembles all four message formats at once.
  def build
    # A Ruby Hash literal is returned here, since this is the last
    # expression evaluated in the method, it's automatically the method's
    # return value (no explicit `return` keyword needed). Each key names
    # one message format, and each value is produced by calling one of the
    # private "build_*" methods defined further down.
    {
      subject:   build_subject,
      text_body: build_text_body,
      html_body: build_html_body,
      sms_body:  build_sms_body
    }
  end
  # `end` closes the `def build` method definition above.

  # `private` marks every method below as internal-only, meant to be
  # called only from other methods within this same class (like `build`
  # above), not from outside code.
  private

  def build_subject
    # `.length` on an Array (here, @triggered_units) returns how many
    # elements it has, i.e., how many units triggered this alert.
    count = @triggered_units.length
    # `case @rule.trigger_type when ... when ... end` is Ruby's
    # multi-branch conditional (similar to switch/case in other
    # languages). It compares @rule.trigger_type against each `when`
    # value in turn and runs the matching branch's code.
    case @rule.trigger_type
    when "price_drop"
      # String interpolation `#{...}` embeds a Ruby expression's value
      # into a String. `"s" if count != 1` is a modifier-if used INSIDE
      # the interpolation: if there's more than one (or zero) units, it
      # adds a pluralizing "s"; if count is exactly 1, the modifier-if's
      # condition is false, so it evaluates to `nil`, which interpolates
      # as an empty string, giving "1 unit dropped" vs "2 units dropped."
      "Price drop detected, #{count} unit#{"s" if count != 1} dropped in price"
    when "price_threshold"
      "#{count} unit#{"s" if count != 1} below $#{@rule.threshold_price}"
    end
    # `end` closes the `case` statement above. Whichever `when` branch ran
    # (or `nil` if trigger_type matched neither) becomes this method's
    # return value, since it's the last expression evaluated.
  end
  # `end` closes the `def build_subject` method definition above.

  def build_text_body
    # `lines = [ "Alert rule: #{@rule.name}", "" ]` starts an Array
    # containing a header line and an empty string (used as a blank line
    # separator once everything is joined together at the end).
    lines = [ "Alert rule: #{@rule.name}", "" ]

    # `.first(10)` returns (at most) the first 10 elements of the
    # triggered_units array, this caps how many units get individually
    # listed in the message body, so a rule that matches hundreds of units
    # doesn't produce an enormous email/notification.
    @triggered_units.first(10).each do |item|
      # `item` is one Hash like `{ unit: ..., previous_price: ... }` (built
      # back in AlertCheckerJob#check_rule). Pull out the pieces we need.
      unit     = item[:unit]
      # `unit.facility` follows the ActiveRecord association from a Unit
      # record to its parent Facility record (this may trigger a database
      # query here if it wasn't eager-loaded already).
      facility = unit.facility

      # `lines <<` appends each formatted line onto the lines array, one
      # per piece of information about this triggered unit.
      lines << "#{facility.company}, #{facility.name}"
      lines << "  Address: #{facility.full_address}"
      lines << "  Size: #{unit.size}"
      lines << "  Price: #{unit.formatted_price}"

      # Only add "previous price"/"change" lines if we actually have a
      # previous price to compare against (it may be nil for a brand new
      # unit, or on the very first crawl).
      if item[:previous_price]
        # `unit.best_price - item[:previous_price]` computes the price
        # difference (current best price minus what it used to be), a
        # negative number means the price dropped, positive means it rose.
        change = unit.best_price - item[:previous_price]
        lines << "  Previous price: $#{item[:previous_price]}"
        # `change >= 0 ? "+" : ""` prepends a literal "+" sign only when
        # the change is zero or positive, so price increases read as
        # "+$5.00" while drops naturally already show a "-" from the
        # negative number itself. `.round(2)` rounds to 2 decimal places
        # (cents), since this is a dollar amount.
        lines << "  Change: #{change >= 0 ? "+" : ""}$#{change.round(2)}"
      end
      # `end` closes the `if item[:previous_price]` block above.

      lines << "  Book: #{unit.booking_url}"
      # An empty string line here becomes a blank line when everything is
      # joined at the end, visually separating this unit's block from the
      # next one in the loop.
      lines << ""
    end
    # `end` closes the `@triggered_units.first(10).each do |item|` loop.

    # If there were more than 10 matching units, mention how many were
    # left out (since we only listed the first 10 above), instead of
    # silently truncating the list with no explanation.
    if @triggered_units.length > 10
      lines << "... and #{@triggered_units.length - 10} more units."
      lines << "Open StorageFinder dashboard for full results."
    end
    # `end` closes the `if @triggered_units.length > 10` block above.

    # `.join("\n")` combines every element of the lines array into one
    # single String, inserting a newline character (`\n`) between each
    # element, turning our array-of-lines into an actual multi-line block
    # of text suitable for an email body.
    lines.join("\n")
  end
  # `end` closes the `def build_text_body` method definition above.

  def build_html_body
    # Simple HTML table format for email
    #
    # `.map do |item| ... end` transforms each of the first 10 triggered
    # units into one HTML `<tr>` (table row) string, collecting the
    # results into a new array called `rows` (unlike `.each`, `.map`
    # returns a new array built from the block's return value each time,
    # rather than the original collection).
    rows = @triggered_units.first(10).map do |item|
      unit     = item[:unit]
      facility = unit.facility
      # `item[:previous_price] ? (...).round(2) : nil` is a ternary: only
      # compute the price change if we have a previous price to compare;
      # otherwise `change` stays nil.
      change   = item[:previous_price] ? (unit.best_price - item[:previous_price]).round(2) : nil

      # `<<~HTML ... HTML` is a Ruby "squiggly heredoc", a way of writing
      # a multi-line String literal directly in the source code. `<<~`
      # (versus plain `<<`) also strips the common leading indentation
      # from every line, so the HTML doesn't come out with extra spaces
      # baked in just because it's visually indented to match the Ruby
      # code around it. Everything between `<<~HTML` and the closing
      # `HTML` marker is the String's content, with `#{...}` interpolation
      # still working inside it just like in a regular double-quoted string.
      <<~HTML
        <tr>
          <td>#{facility.company}</td>
          <td>#{facility.name}</td>
          <td>#{unit.size}</td>
          <td>#{unit.formatted_price}</td>
          #{ change ? "<td>#{change >= 0 ? "+" : ""}$#{change}</td>" : "<td>—</td>" }
          <td><a href="#{unit.booking_url}">Book now</a></td>
        </tr>
      HTML
      # This nested ternary builds the "Change" table cell: if `change` is
      # present, show it with a +/- sign; otherwise show an em-dash "—" as
      # a placeholder meaning "no previous price to compare."
    end
    # `end` closes the `.map do |item|` block above. `rows` now holds one
    # HTML `<tr>...</tr>` string per triggered unit (up to 10).

    # Another heredoc builds the full HTML page/email body, embedding the
    # already-built `rows` array (joined together with no separator via
    # `rows.join`, since each row string already ends in a newline from
    # the heredoc formatting) into an HTML `<table>`.
    <<~HTML
      <html><body>
        <h2>StorageFinder Alert: #{build_subject}</h2>
        <p>Rule: <strong>#{@rule.name}</strong></p>
        <table border="1" cellpadding="5" style="border-collapse:collapse">
          <tr>
            <th>Company</th><th>Facility</th><th>Size</th>
            <th>Price</th><th>Change</th><th>Book</th>
          </tr>
          #{rows.join}
        </table>
        #{@triggered_units.length > 10 ? "<p>...and #{@triggered_units.length - 10} more units.</p>" : ""}
      </body></html>
    HTML
    # This heredoc is the LAST expression evaluated in the method, so its
    # resulting String is what build_html_body returns.
  end
  # `end` closes the `def build_html_body` method definition above.

  def build_sms_body
    # SMS must be very short
    #
    # `@triggered_units.first` returns just the single first element of
    # the array (not wrapped in an array, unlike `.first(1)` which would
    # return a one-element array), SMS messages are short, so only the
    # single most relevant unit is described, unlike the text/HTML bodies
    # which list up to 10.
    unit     = @triggered_units.first[:unit]
    facility = unit.facility
    # A single interpolated String summarizing the company, unit size,
    # price, city, and a link, kept intentionally terse since SMS
    # messages have character-length/cost constraints.
    "StorageFinder: #{facility.company} #{unit.size} #{unit.formatted_price} at #{facility.city}. #{unit.booking_url}"
  end
  # `end` closes the `def build_sms_body` method definition above.
end
# `end` closes the `class AlertMessageBuilder` definition that started at
# the top of this file.
