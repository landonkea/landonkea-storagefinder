# Loads test/test_helper.rb, which boots the Rails app in test mode and sets
# up shared test infrastructure (Minitest, fixture loading, etc.), every
# test file in this app starts with this same line. See
# test/models/alert_rule_test.rb or test/test_helper.rb for a fuller
# explanation of what this line does and why it's needed.
require "test_helper"

# An automated test suite for the CrawlLogEntry model (see
# app/models/crawl_log_entry.rb), a test suite is a group of related,
# automatically-runnable checks. `class CrawlLogEntryTest <
# ActiveSupport::TestCase` inherits from Rails' base test class, which is
# what makes the `test "..." do ... end` blocks below, the `assert_*` /
# `refute_*` methods, and fixture lookups like `crawl_runs(:...)` all work.
class CrawlLogEntryTest < ActiveSupport::TestCase
  # A plain Ruby helper method (not a test itself) that returns a Hash of
  # attributes describing a VALID CrawlLogEntry, so each test below doesn't
  # need to repeat this setup.
  def valid_attributes
    # `crawl_runs(:current_completed)` is a FIXTURE lookup: fixtures are
    # pre-made, fake database rows defined in YAML files under
    # test/fixtures/ (here, test/fixtures/crawl_runs.yml) and automatically
    # loaded into the test database before every test runs. This call
    # returns the real, already-saved CrawlRun record built from the
    # `current_completed:` entry in that file, used here to satisfy
    # CrawlLogEntry's `belongs_to :crawl_run` requirement (every log entry
    # must belong to a real crawl run).
    { crawl_run: crawl_runs(:current_completed), company: "Test Co", message: "hello", level: "info" }
  end
  # `end` closes the `def valid_attributes` method definition.

  # `test "..." do ... end` defines one individual automated test (see
  # test/models/alert_rule_test.rb for a fuller explanation of this syntax,
  # provided by ActiveSupport::Testing::Declarative). Running the whole
  # suite executes every one of these blocks and reports pass/fail for each.
  test "requires company and message" do
    # `CrawlLogEntry.new(...)` builds a new, unsaved record in memory.
    # `valid_attributes.merge(company: "", message: "")` takes the valid
    # Hash from above and returns a NEW Hash with `company` and `message`
    # both overwritten to empty strings, to intentionally violate the
    # model's presence validations on those two fields.
    entry = CrawlLogEntry.new(valid_attributes.merge(company: "", message: ""))
    # `refute entry.valid?`, `.valid?` runs every validation defined in
    # app/models/crawl_log_entry.rb and returns true/false; `refute`
    # (Minitest's "expect false" assertion) fails this test unless the
    # blank company/message actually make the record invalid.
    refute entry.valid?
    # `entry.errors[:company]` reads the array of validation-error messages
    # attached specifically to the `company` field (populated as a side
    # effect of the `.valid?` call above). `assert_includes array, item`
    # checks that `item` appears somewhere in `array`, here, that the
    # model's custom presence-validation message shows up.
    assert_includes entry.errors[:company], "Company is required on a log entry"
    # Same idea for the `message` field's error messages.
    assert_includes entry.errors[:message], "Log message cannot be blank"
  end
  # `end` closes this `test` block.

  test "level must be info, warning, or error" do
    # Overrides `level` to a value NOT in the model's allowed list
    # (`%w[info warning error]` in app/models/crawl_log_entry.rb).
    entry = CrawlLogEntry.new(valid_attributes.merge(level: "critical"))
    refute entry.valid?
    assert_includes entry.errors[:level], "Log level must be 'info', 'warning', or 'error'"
  end
  # `end` closes this `test` block.

  test "scopes filter by level" do
    # `crawl_log_entries(:error_entry)` and `crawl_log_entries(:info_entry)`
    # look up two different fixtures (fake, pre-saved rows) defined in
    # test/fixtures/crawl_log_entries.yml, one with `level: error` and one
    # with `level: info`.
    #
    # `CrawlLogEntry.errors` calls the `errors` SCOPE defined in
    # app/models/crawl_log_entry.rb (`where(level: "error")`), a query for
    # every log entry whose level is "error". `assert_includes` checks the
    # error_entry fixture shows up in that query's results.
    assert_includes CrawlLogEntry.errors, crawl_log_entries(:error_entry)
    # `refute_includes` is the opposite check, confirms the info_entry
    # fixture (level "info") is correctly EXCLUDED from the `errors` scope.
    refute_includes CrawlLogEntry.errors, crawl_log_entries(:info_entry)
    # Confirms the `infos` scope (`where(level: "info")`) correctly INCLUDES
    # the info_entry fixture.
    assert_includes CrawlLogEntry.infos, crawl_log_entries(:info_entry)
  end
  # `end` closes this `test` block.

  test "to_log_line includes timestamp, level, company, and message" do
    # Loads the error_entry fixture, see test/fixtures/crawl_log_entries.yml
    # for its exact stored values (level: error, company: "Public Storage",
    # a timeout message, retry_count: 3).
    entry = crawl_log_entries(:error_entry)
    # `entry.to_log_line` calls the instance method defined in
    # app/models/crawl_log_entry.rb, which builds one formatted text line
    # combining the timestamp, level, company, message, and (if present) a
    # retry count, the same format written to the app's log file.
    line = entry.to_log_line

    # `assert_includes string, substring` also works for checking that one
    # string CONTAINS another (Ruby Strings support `.include?`, which
    # `assert_includes` uses under the hood, it isn't limited to arrays).
    # `entry.level.upcase` converts "error" to "ERROR", to_log_line
    # uppercases the level when building the line, so this checks that
    # transformation happened.
    assert_includes line, entry.level.upcase
    # Confirms the company name appears somewhere in the formatted line.
    assert_includes line, entry.company
    # Confirms the original message text appears somewhere in the line.
    assert_includes line, entry.message
    # The error_entry fixture has retry_count: 3, and to_log_line appends
    # "(retry N)" whenever retry_count is greater than 0, this checks that
    # exact substring appears.
    assert_includes line, "retry 3"
  end
  # `end` closes this `test` block.

  test "css_class maps level to a CSS class" do
    # `CrawlLogEntry.new(level: "error")` builds a brand-new, unsaved record
    # with ONLY the `level` attribute set (no company/message, this is
    # fine here since we're never calling `.valid?` or `.save`, just reading
    # the `css_class` method, which doesn't depend on those other fields).
    # `.css_class` (see app/models/crawl_log_entry.rb) maps the level string
    # to a CSS class name used for color-coding log lines in the dashboard.
    # `assert_equal expected, actual` is Minitest's most common assertion:
    # it fails unless the two values are exactly equal (`==`).
    assert_equal "log-error",   CrawlLogEntry.new(level: "error").css_class
    assert_equal "log-warning", CrawlLogEntry.new(level: "warning").css_class
    assert_equal "log-info",    CrawlLogEntry.new(level: "info").css_class
  end
  # `end` closes this `test` block.

  test "emoji_prefix maps level to an emoji" do
    # Same pattern as css_class above, but checking the emoji_prefix method
    # (used when formatting Discord alert messages) returns the correct
    # emoji character for each level.
    assert_equal "🔴", CrawlLogEntry.new(level: "error").emoji_prefix
    assert_equal "🟡", CrawlLogEntry.new(level: "warning").emoji_prefix
    assert_equal "🟢", CrawlLogEntry.new(level: "info").emoji_prefix
  end
  # `end` closes this `test` block.
end
# `end` closes the `class CrawlLogEntryTest < ActiveSupport::TestCase` block
# that started at the top of this file.
