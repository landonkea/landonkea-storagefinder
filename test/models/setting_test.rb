# Loads test/test_helper.rb, which boots the Rails app in test mode and sets
# up shared test infrastructure (Minitest, fixture loading, etc.). See
# test/test_helper.rb or test/models/alert_rule_test.rb for a fuller
# explanation of what this line does.
require "test_helper"

# An automated test suite for the Setting model (see app/models/setting.rb)
#, a simple key/value configuration store used throughout this app instead
# of hardcoded config files. `class SettingTest < ActiveSupport::TestCase`
# inherits from Rails' base test class, providing the `test "..." do ... end`
# syntax below, the `assert_*`/`refute_*` assertion methods, and fixture
# lookups like `settings(:...)`.
class SettingTest < ActiveSupport::TestCase
  # `test "..." do ... end` defines one individual automated test (see
  # test/models/alert_rule_test.rb for a full explanation of this Rails/
  # Minitest syntax).
  test "get returns the cast value for an existing key" do
    # `Setting.get("crawl_default_radius_miles")` calls the class method
    # defined in app/models/setting.rb, which looks up a Setting row by its
    # `key` column and converts (or "casts") the raw stored string into the
    # appropriate Ruby type based on that row's `input_type` column. This
    # key's fixture (see test/fixtures/settings.yml) has `input_type:
    # number` and `value: "100"`, so `.get` should return the actual
    # Integer 100 rather than the raw string "100".
    #
    # `assert_equal expected, actual` fails unless the two values are
    # exactly (`==`) equal, importantly, in Ruby the integer `100` and the
    # string `"100"` are NOT `==` to each other, so this assertion also
    # confirms the type conversion actually happened, not just that the
    # underlying text matched.
    assert_equal 100, Setting.get("crawl_default_radius_miles")
    # This key's fixture has `input_type: boolean` and `value: "true"`, a
    # correct cast should produce the actual Ruby boolean `true`, not the
    # string "true".
    assert_equal true, Setting.get("crawl_headless")
    # This key's fixture has `input_type: text`, text values are simply
    # returned as-is (already a string), so no conversion is visible here,
    # but it confirms the "text" branch of the model's casting logic works.
    assert_equal "smtp.gmail.com", Setting.get("email_smtp_host")
  end
  # `end` closes this `test` block.

  test "get returns the default when the key doesn't exist" do
    # No fixture defines a Setting with this key, so `find_by(key: ...)`
    # inside Setting.get (see app/models/setting.rb) returns nil, and with
    # no `default:` argument supplied, `.get` should return nil too.
    # `assert_nil` is a Minitest assertion that fails unless its argument is
    # exactly `nil`.
    assert_nil Setting.get("nonexistent_key")
    # This time an explicit `default:` keyword argument is supplied, since
    # the key still doesn't exist, `.get` should return THIS fallback value
    # instead of nil.
    assert_equal "fallback", Setting.get("nonexistent_key", default: "fallback")
  end
  # `end` closes this `test` block.

  test "set updates an existing setting's value" do
    # `Setting.set(key, value)` (see app/models/setting.rb) is an "upsert"
    # (update-or-insert) class method: since a Setting row with this key
    # already exists (from test/fixtures/settings.yml), this call updates
    # its stored value rather than creating a second row.
    Setting.set("crawl_default_radius_miles", "250")
    # Reading it back via `.get` (which also casts to the right type per
    # `input_type: number`) confirms the new value was actually saved and
    # is returned as the Integer 250, not the string "250".
    assert_equal 250, Setting.get("crawl_default_radius_miles")
  end
  # `end` closes this `test` block.

  test "set creates a new setting when the key doesn't already exist" do
    # `Setting.find_by(key: "brand_new_key")` looks for an existing row with
    # this key directly (bypassing the `.get` casting logic used elsewhere
    # in this file), confirming, before calling `.set`, that no such row
    # exists yet.
    assert_nil Setting.find_by(key: "brand_new_key")
    # Calls `.set` with a key that has never been seen before, since
    # `find_or_initialize_by` inside the model (see app/models/setting.rb)
    # falls back to building a brand-new record when nothing matches, this
    # should create (and save) a new Setting row.
    Setting.set("brand_new_key", "hello")
    # `Setting.find_by(key: "brand_new_key").value` looks the row up again
    # and reads its `value` column DIRECTLY (not through `.get`'s casting
    # logic, this new setting has no `input_type` set, so `.get` would
    # treat it as plain text anyway, but this line is checking the raw
    # attribute access path instead). Confirms the row now exists with the
    # value that was just set.
    assert_equal "hello", Setting.find_by(key: "brand_new_key").value
  end
  # `end` closes this `test` block.

  test "enabled? returns true only for boolean settings set to true" do
    # `Setting.enabled?(key)` (see app/models/setting.rb) calls `.get` and
    # compares the result against the literal boolean `true`, this
    # fixture's key has `input_type: boolean` and `value: "true"`, so it
    # should come back enabled.
    assert Setting.enabled?("crawl_headless")
    # This fixture (see test/fixtures/settings.yml) has `input_type:
    # boolean` but `value: "false"`, `enabled?` should correctly report
    # false rather than any other "truthy" Ruby value.
    refute Setting.enabled?("email_enabled")
  end
  # `end` closes this `test` block.

  test "get_all scopes to a category" do
    # `Setting.get_all("email")` (see app/models/setting.rb) queries every
    # Setting row whose `category` column is "email" and returns them as a
    # single Ruby Hash of key => cast_value pairs.
    email_settings = Setting.get_all("email")
    # `.key?("email_smtp_host")` is a Hash method checking whether that
    # exact key exists in the Hash (regardless of its value), confirms an
    # "email" category setting made it into the result.
    assert email_settings.key?("email_smtp_host")
    # `crawl_headless` belongs to the "crawl" category, not "email" (see
    # test/fixtures/settings.yml), confirms `get_all("email")` correctly
    # EXCLUDES settings from other categories.
    refute email_settings.key?("crawl_headless")
  end
  # `end` closes this `test` block.

  test "value is stored encrypted in the database" do
    # `settings(:email_smtp_host)` is a FIXTURE lookup: fixtures are
    # pre-made, fake database rows defined in YAML files under
    # test/fixtures/ (here, test/fixtures/settings.yml), automatically
    # loaded into the test database before every test runs.
    setting = settings(:email_smtp_host)

    # `ActiveRecord::Base.connection` gives direct, low-level access to the
    # underlying database connection, bypassing ActiveRecord's normal
    # attribute-reading machinery entirely (which would automatically
    # decrypt the `value` column, see `encrypts :value` in
    # app/models/setting.rb). `.select_value(sql)` runs a raw SQL query and
    # returns just the single value from the first row/column of the
    # result, here, the RAW (still-encrypted) bytes stored for this row's
    # `value` column. `#{setting.id}` interpolates this record's database id
    # directly into the SQL string.
    raw_value = ActiveRecord::Base.connection.select_value(
      "SELECT value FROM settings WHERE id = #{setting.id}"
    )

    # `refute_equal expected_to_NOT_match, actual` is the opposite of
    # `assert_equal`, it fails if the two values ARE equal. The optional
    # third argument (here, a custom failure message string) is what
    # Minitest prints if the assertion fails, making a failure easier to
    # understand than the default generic message. This confirms the RAW
    # database bytes are NOT the plaintext "smtp.gmail.com", i.e. Active
    # Record Encryption is actually encrypting the column at rest, not just
    # claiming to.
    refute_equal "smtp.gmail.com", raw_value, "raw DB column should not contain the plaintext value"
    # `setting.reload` re-fetches this record's attributes fresh from the
    # database THROUGH normal ActiveRecord (which transparently decrypts
    # `value` on the way out), confirms that, from the application's point
    # of view, reading `.value` still transparently returns the original
    # plaintext despite the ciphertext stored underneath.
    assert_equal "smtp.gmail.com", setting.reload.value, "AR-level access should transparently decrypt"
  end
  # `end` closes this `test` block.

  test "key must be unique" do
    # Builds a brand-new, unsaved Setting reusing an EXISTING fixture's key
    # (`settings(:email_enabled).key`), this should trip the model's
    # `uniqueness: { message: "..." }` validation on `key` (see
    # app/models/setting.rb).
    duplicate = Setting.new(key: settings(:email_enabled).key, value: "x", input_type: "text")
    refute duplicate.valid?
    assert_includes duplicate.errors[:key], "A setting with this key already exists"
  end
  # `end` closes this `test` block.
end
# `end` closes the `class SettingTest < ActiveSupport::TestCase` block that
# started at the top of this file.
