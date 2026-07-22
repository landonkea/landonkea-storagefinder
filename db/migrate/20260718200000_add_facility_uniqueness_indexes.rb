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

class AddFacilityUniquenessIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :facilities, [ :company, :external_id ],
      unique: true,
      where:  "external_id IS NOT NULL",
      name:   "index_facilities_on_company_and_external_id_uniq"

    add_index :facilities, [ :company, :address, :city, :state ],
      unique: true,
      where:  "external_id IS NULL",
      name:   "index_facilities_on_company_and_address_uniq"
  end
end
