# =============================================================================
# ADD COOLDOWN_MINUTES TO ALERT_RULES
# =============================================================================
# AlertRule#record_triggered! stamps last_triggered_at every time a rule
# fires, but nothing previously stopped the SAME rule from firing again on
# the very next crawl if the condition (still) matched, e.g. a
# price_threshold rule for "under $100" would re-send an alert after EVERY
# crawl for as long as the price stayed under $100, not just once when it
# first dropped below. This migration adds an optional "quiet hours" window
# (in minutes) a rule can set for itself: once it fires, it won't fire again
# until that many minutes have passed, even if the trigger condition still
# matches on a later crawl. See AlertRule#in_cooldown? and
# AlertCheckerJob#check_rule for how this column is actually used.
# =============================================================================

# `class AddCooldownMinutesToAlertRules < ActiveRecord::Migration[8.1]`, see
# db/migrate/20260718200000_add_facility_uniqueness_indexes.rb for a fuller
# narrated explanation of what a Rails migration is and how the `[8.1]`
# version suffix works. Short version: each migration is a one-off, ordered
# database change; the filename's leading timestamp
# (20260803000000) is how Rails knows this one runs AFTER every
# already-applied migration with an earlier timestamp.
class AddCooldownMinutesToAlertRules < ActiveRecord::Migration[8.1]
  # `change` is the conventional method name Rails looks for in a migration
  #, it describes the schema change to make, and (for simple,
  # automatically-reversible operations like `add_column`) Rails can also
  # figure out how to UNDO this same change if the migration is ever rolled
  # back, without a separate `down` method needing to be written by hand.
  def change
    # `add_column :alert_rules, :cooldown_minutes, :integer, default: 0,
    # null: false` adds a new integer column to the existing "alert_rules"
    # table. `default: 0` means every existing row (and any new row that
    # doesn't explicitly set this) gets 0, which, per AlertRule#in_cooldown?
    # below, means "no cooldown configured, fire every time the condition
    # matches", i.e. today's existing behavior is fully preserved for every
    # rule until someone opts into a cooldown window. `null: false` requires
    # every row to have SOME integer value (never a missing/nil column),
    # which is safe here precisely because `default: 0` guarantees one.
    add_column :alert_rules, :cooldown_minutes, :integer, default: 0, null: false
  end
  # `end` closes the `def change` method definition above.
end
# `end` closes the `class AddCooldownMinutesToAlertRules` definition that
# started at the top of this file.
