# =============================================================================
# APPLICATION RECORD
# =============================================================================
# This is the base class that all models inherit from.
# Rails requires it — don't delete it.
# You can add methods here that should be available on ALL models.
# =============================================================================

# `class ApplicationRecord < ActiveRecord::Base` defines a Ruby class named
# ApplicationRecord that INHERITS from `ActiveRecord::Base` (the `<` symbol
# means "inherits from"). ActiveRecord is the part of Rails that connects
# Ruby objects to database tables — a class that inherits from
# `ActiveRecord::Base` (directly, or indirectly like the models below that
# inherit from ApplicationRecord instead) automatically gets methods like
# `.find`, `.where`, `.save`, and `.create` for talking to the database,
# without you writing any SQL by hand. Every other model file in this app
# (AlertRule, Facility, Unit, etc.) inherits from ApplicationRecord rather
# than straight from ActiveRecord::Base, so anything added here is shared by
# every model in the whole application.
class ApplicationRecord < ActiveRecord::Base
  # `primary_abstract_class` is a Rails class method that marks
  # ApplicationRecord as "abstract" — meaning Rails should NOT look for a
  # database table called "application_records". Without this, Rails would
  # try (and fail) to treat this class as a real, queryable table. This line
  # exists purely so ApplicationRecord can serve as a shared base class for
  # the real models (which each map to their own table, e.g. Unit -> "units").
  primary_abstract_class   # Tells Rails this is a base class, not a real table

  # ---------------------------------------------------------------------------
  # SHARED SCOPE — available on all models
  # ---------------------------------------------------------------------------

  # A "scope" is Rails' way of defining a named, reusable database query that
  # you can call like a method, e.g. `Facility.recent_days(7)`. Here, `scope`
  # is a Rails class method; `:recent_days` is a Ruby "symbol" (a lightweight,
  # immutable label used as a name/identifier — symbols start with `:` and are
  # commonly used for names like this rather than plain strings). The second
  # argument, `->(n) { ... }`, is a Ruby "lambda" — an anonymous, reusable
  # chunk of code. `->(n)` declares that the lambda takes one argument named
  # `n`; the code inside the `{ }` braces is what runs when the scope is
  # called, with `n` filled in by whatever value the caller passed.
  #
  # Returns records created in the last N days
  # Usage: Facility.recent_days(7) — facilities created in the last week
  scope :recent_days, ->(n) { where("created_at >= ?", n.days.ago) }
  # `where("created_at >= ?", n.days.ago)` builds a SQL query fragment. The
  # `?` is a placeholder that Rails safely substitutes with the second
  # argument — this avoids SQL injection, which is why you should always use
  # `?` placeholders instead of directly interpolating user input into SQL
  # strings. `n.days.ago` is Rails' friendly date math: `n` is a plain
  # integer, `.days` converts it into a duration of `n` days, and `.ago`
  # subtracts that duration from the current time, giving a Time/DateTime
  # value representing "n days before right now." Because this scope is
  # defined on ApplicationRecord, EVERY model that inherits from it
  # (Facility, Unit, CrawlRun, etc.) automatically gets a `.recent_days(n)`
  # method for free, filtered to that model's own `created_at` column.
end
# `end` closes the `class ApplicationRecord < ActiveRecord::Base` block that
# started at the top of the file — everything above it is part of this class.
