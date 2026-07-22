# =============================================================================
# APPLICATION RECORD
# =============================================================================
# This is the base class that all models inherit from.
# Rails requires it — don't delete it.
# You can add methods here that should be available on ALL models.
# =============================================================================

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class   # Tells Rails this is a base class, not a real table

  # ---------------------------------------------------------------------------
  # SHARED SCOPE — available on all models
  # ---------------------------------------------------------------------------

  # Returns records created in the last N days
  # Usage: Facility.recent_days(7) — facilities created in the last week
  scope :recent_days, ->(n) { where("created_at >= ?", n.days.ago) }
end
