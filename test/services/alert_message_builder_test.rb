# `require "test_helper"` loads test/test_helper.rb, which boots Rails in
# test mode and loads the fixture data (units, facilities, alert rules)
# this file's tests rely on.
require "test_helper"

# This file tests AlertMessageBuilder (app/services/alerting/alert_message_builder.rb)
#, the class that formats the subject/text/HTML/SMS content of an alert
# notification, given an AlertRule and a list of units that triggered it.
# It does NOT test delivery (that's AlertDeliveryService, covered in
# alert_delivery_service_test.rb), just the message content itself.
class AlertMessageBuilderTest < ActiveSupport::TestCase
  # `def triggered_units` defines a helper method (not a `test` block)
  # shared by every test below. It builds a small Array of Hashes matching
  # the shape AlertCheckerJob passes into AlertMessageBuilder.build (see
  # app/jobs/alert_checker_job.rb's `triggered_units << { unit:, previous_price: }`)
  #, one entry per unit that "triggered" an alert, each holding the Unit
  # record itself plus its price from the previous crawl (or nil if there
  # was none).
  def triggered_units
    [
      # `units(:current_gilbert_10x10)` looks up a Unit fixture by name (see
      # test/fixtures/units.yml). This entry has a `previous_price` of 150,
      # simulating a unit whose price is being compared to an earlier
      # crawl's $150.
      { unit: units(:current_gilbert_10x10), previous_price: 150 },
      # This second entry has `previous_price: nil`, simulating a unit with
      # no earlier price to compare against (e.g. the first time this
      # facility/size combination was ever seen).
      { unit: units(:current_mesa_10x15), previous_price: nil }
    ]
  end
  # `end` closes the `def triggered_units` helper method definition above.

  test "build returns subject, text_body, html_body, and sms_body" do
    # `AlertMessageBuilder.build(rule, triggered_units)` calls the class
    # method (app/services/alerting/alert_message_builder.rb) that builds a
    # new AlertMessageBuilder instance and runs `.build` on it, returning a
    # Hash with the four keys checked below. `alert_rules(:price_drop_rule)`
    # looks up that AlertRule fixture; `triggered_units` here calls the
    # helper method defined above (not a local variable, Ruby only tells
    # them apart by whether a local variable with that name already exists
    # in scope, and here it doesn't, so this is a method call).
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    # `message[:subject].present?` reads the Hash's `:subject` key (Ruby
    # Hash access via square brackets) and checks it's not nil/blank via
    # Rails' `.present?` helper. `assert` alone (no custom message) just
    # requires its argument to be truthy to pass. Repeating this for all
    # four keys confirms AlertMessageBuilder.build always returns a
    # complete Hash with real content in every field.
    assert message[:subject].present?
    assert message[:text_body].present?
    assert message[:html_body].present?
    assert message[:sms_body].present?
  end
  # `end` closes the "build returns subject, text_body..." test block above.

  test "price_drop subject mentions the number of units" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)
    # `assert_match(/2 units dropped in price/, message[:subject])` checks
    # the subject string CONTAINS this exact text, using a Ruby Regexp
    # literal (`/.../`) as a pattern to search for. Since `triggered_units`
    # above returns exactly 2 entries, this confirms build_subject (see
    # app/services/alerting/alert_message_builder.rb) correctly counts them
    # and pluralizes "unit" → "units".
    assert_match(/2 units dropped in price/, message[:subject])
  end
  # `end` closes the "price_drop subject mentions the number of units" test block above.

  test "price_threshold subject mentions the threshold" do
    message = AlertMessageBuilder.build(alert_rules(:price_threshold_rule), triggered_units)
    # Confirms the subject for a "price_threshold"-type rule includes its
    # dollar threshold value, `\$100\.0` in the regex escapes the literal
    # `$` and `.` characters (both of which have special meaning in regular
    # expressions otherwise: `$` normally means "end of line" and `.`
    # normally means "any character") so they're matched as literal text
    # instead.
    assert_match(/below \$100\.0/, message[:subject])
  end
  # `end` closes the "price_threshold subject mentions the threshold" test block above.

  test "text_body lists each unit's facility, size, and price" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    # `assert_match "Public Storage", message[:text_body]`, here the first
    # argument is a plain String, not a Regexp; `assert_match` accepts
    # either, and for a String it just checks that the second argument
    # contains it as a literal substring. This confirms the text body
    # includes the facility's company name (fixture-derived, see
    # test/fixtures/facilities.yml).
    assert_match "Public Storage", message[:text_body]
    assert_match "10x10", message[:text_body]
    # This one uses a Regexp again (needed because of the `$` and the
    # specific number formatting) to confirm the PREVIOUS price ($150, set
    # in the triggered_units helper above) shows up correctly labeled in
    # the text body.
    assert_match(/Previous price: \$150/, message[:text_body])
  end
  # `end` closes the "text_body lists each unit's facility, size, and
  # price" test block above.

  test "text_body truncates to 10 units and notes how many more there are" do
    # `(1..12).map { { unit: ..., previous_price: nil } }` builds an Array
    # with 12 entries. `(1..12)` is a Ruby Range literal (the integers 1
    # through 12, inclusive); `.map { ... }` runs the block once per number
    # in the range and collects each block's return value into a new
    # Array, since the block ignores the actual number and always returns
    # the same Hash shape, the result is simply 12 (nearly) identical
    # triggered-unit entries, useful here purely to test what happens with
    # MORE than 10 units, without needing 12 distinct unit fixtures.
    many_units = (1..12).map { { unit: units(:current_gilbert_10x10), previous_price: nil } }
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), many_units)

    # Confirms build_text_body (see alert_message_builder.rb, which lists
    # `.first(10)` units then appends a "...and N more units" line) reports
    # exactly 2 extra units beyond the 10 shown, matching 12 total minus 10.
    assert_match(/and 2 more units/, message[:text_body])
  end
  # `end` closes the "text_body truncates to 10 units..." test block above.

  test "html_body renders a table row per unit" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    # `message[:html_body].scan("<tr>")` is Ruby's String#scan, it finds
    # EVERY occurrence of the substring "<tr>" (an HTML "table row" opening
    # tag) in the html_body string and returns them all as an Array (one
    # entry per match), so `.length` gives the total count of "<tr>" tags.
    # build_html_body (see alert_message_builder.rb) emits one header row
    # PLUS one row per triggered unit, so subtracting 1 (for the header
    # row) should leave exactly 2, matching the 2 entries `triggered_units`
    # returns.
    assert_equal 2, message[:html_body].scan("<tr>").length - 1 # -1 for the header row
  end
  # `end` closes the "html_body renders a table row per unit" test block above.

  test "sms_body is a single short line about the first unit" do
    message = AlertMessageBuilder.build(alert_rules(:price_drop_rule), triggered_units)

    assert_match "Public Storage", message[:sms_body]
    # `refute_includes message[:sms_body], "\n"` is Minitest's negative
    # assertion counterpart to `assert_includes`, it passes only if the
    # sms_body string does NOT contain a newline character (`"\n"` is
    # Ruby's escape sequence for a single newline). This confirms
    # build_sms_body (see alert_message_builder.rb) really does produce one
    # single-line message, appropriate for a text message rather than a
    # multi-line email body.
    refute_includes message[:sms_body], "\n"
  end
  # `end` closes the "sms_body is a single short line..." test block above.
end
# `end` closes the `class AlertMessageBuilderTest < ActiveSupport::TestCase`
# definition that started at the top of this file.
