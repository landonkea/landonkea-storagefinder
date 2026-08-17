# =============================================================================
# API KEY MODEL
# =============================================================================
# An ApiKey grants programmatic (non-browser) access to the read-only JSON
# API under /api/v1 (see app/controllers/api/base_controller.rb and
# config/routes.rb). Keys are issued/revoked from the admin-only UI at
# /api_keys, which sits behind the same HTTP Basic Auth as the rest of the
# dashboard — but requests to /api/v1/* authenticate with the key's token
# instead, so external scripts/integrations don't need the site password.
# =============================================================================

class ApiKey < ApplicationRecord
  # `has_secure_token` is a Rails built-in: it auto-generates a unique,
  # random, URL-safe 24-character string into the `token` column the first
  # time a record is saved (via a `before_create` callback it installs
  # behind the scenes), and adds a `regenerate_token` instance method that
  # assigns and persists a fresh one on demand. It relies on the model
  # having a unique-indexed string column named `token` — added by the
  # CreateApiKeys migration.
  has_secure_token :token

  validates :name, presence: { message: "A label is required so you can tell keys apart" }

  # `active` keys can authenticate; flipping this to false is how a key is
  # revoked without deleting its usage history (last_used_at, request_count).
  scope :active, -> { where(active: true) }

  # Called once per authenticated API request (see
  # Api::BaseController#authenticate_api_key!) to keep basic usage stats
  # without slowing down the request on a validation failure — `update_columns`
  # skips validations/callbacks and issues a single UPDATE.
  def record_usage!
    update_columns(last_used_at: Time.current, request_count: request_count + 1)
  end

  # A shortened, display-safe form of the token for the admin UI — showing
  # the full token again after creation would mean storing/transmitting the
  # secret repeatedly, so only ever show it in full once, right after
  # creation (see ApiKeysController#create).
  def masked_token
    return "" if token.blank?

    "#{token[0, 4]}#{'•' * 12}#{token[-4, 4]}"
  end
end
