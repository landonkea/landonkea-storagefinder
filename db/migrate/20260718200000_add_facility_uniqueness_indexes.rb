# =============================================================================
# ADD FACILITY UNIQUENESS INDEXES
# =============================================================================
# Companies::BaseParser#upsert_facility already dedupes facilities in Ruby via
# find_or_initialize_by: by [company, external_id] when external_id is
# present, otherwise by [company, address, city, state]. That logic only
# protects against duplicates within a single crawl's sequential upserts —
# nothing stops two parallel crawl threads (or a data-entry mistake) from
# both finding "no existing row" at the same instant and inserting two
# facilities for the same real-world location. These indexes make the same
# two rules an actual DB-level guarantee.
# =============================================================================

# `class AddFacilityUniquenessIndexes < ActiveRecord::Migration[8.1]` defines
# a new Ruby class named AddFacilityUniquenessIndexes. The `<` means it
# INHERITS from `ActiveRecord::Migration[8.1]`, reusing Rails' built-in
# migration machinery, versioned to behave like Rails 8.1 (a newer version
# than the [7.1] used in the 2024 migration, since this migration was
# written later against a newer Rails). The `end` at the very bottom of the
# file closes this class definition.
class AddFacilityUniquenessIndexes < ActiveRecord::Migration[8.1]
  # `def change` defines the method Rails runs for this migration — both
  # forwards (`db:migrate`) and, since `add_index` is a change Rails knows
  # how to reverse automatically (by dropping the index again), backwards
  # (`db:rollback`) too, without needing separate "up"/"down" methods. The
  # matching `end` near the bottom of the file (just above the class's
  # closing `end`) closes this method.
  def change
    # `add_index` adds a new INDEX to the existing "facilities" table — an
    # index is a lookup structure similar to a book's index, letting
    # queries jump straight to matching rows instead of scanning every row.
    # `[ :company, :external_id ]` is a Ruby array (list) naming BOTH
    # columns this index covers together, so it can enforce/speed up
    # queries about a (company, external_id) pair as a unit.
    add_index :facilities, [ :company, :external_id ],
      # `unique: true` turns this into a UNIQUE INDEX — the database will
      # refuse to insert (or update) a row whose (company, external_id)
      # pair already exists elsewhere in the table. This is what turns the
      # Ruby-level dedupe logic described in the comment above into a hard
      # guarantee enforced by the database itself, even under concurrent
      # writes.
      unique: true,
      # `where:` makes this a PARTIAL index — it only applies to rows
      # matching this SQL condition, rather than the whole table. Here it
      # only covers rows where "external_id IS NOT NULL" (i.e. rows that
      # actually have an external_id set), matching the Ruby logic's rule
      # of deduping by [company, external_id] specifically when
      # external_id is present.
      where:  "external_id IS NOT NULL",
      # `name:` gives this index an explicit, human-readable name instead
      # of letting Rails auto-generate one — useful for finding it later in
      # database tooling or in a future migration that might need to drop
      # it.
      name:   "index_facilities_on_company_and_external_id_uniq"

    # A second unique index, this time across THREE columns together:
    # company, address, city, and state (four columns, despite the name
    # "company_and_address_uniq" only mentioning two of them).
    add_index :facilities, [ :company, :address, :city, :state ],
      # Again makes this a unique index — the database rejects a second row
      # with the same (company, address, city, state) combination.
      unique: true,
      # This partial index only applies to rows where "external_id IS
      # NULL" (i.e. rows with NO external_id) — the complementary case to
      # the index above, matching the Ruby logic's fallback rule of
      # deduping by [company, address, city, state] when there's no
      # external_id to key off of. Together, these two partial unique
      # indexes cover every row exactly once (a row either has an
      # external_id or it doesn't), without ever conflicting with each
      # other.
      where:  "external_id IS NULL",
      # Explicit, human-readable name for this second index.
      name:   "index_facilities_on_company_and_address_uniq"
  end
  # This `end` closes the `def change` method opened above — both indexes
  # this migration adds have now been fully described.
end
# This final `end` closes the `class AddFacilityUniquenessIndexes <
# ActiveRecord::Migration[8.1]` class definition opened at the top of the
# file.
