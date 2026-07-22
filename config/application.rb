require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Storagefinder
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # ---------------------------------------------------------------------------
    # AUTOLOADING
    # ---------------------------------------------------------------------------
    # Collapse subdirectories that don't use namespacing.
    # This means ReconService (not Recon::ReconService) and
    # AlertDeliveryService (not Alerting::AlertDeliveryService)
    initializer "storagefinder.autoload_collapse", before: :bootstrap_hook do
      Rails.autoloaders.main.collapse("#{config.root}/app/services/recon")
      Rails.autoloaders.main.collapse("#{config.root}/app/services/alerting")
      # companies/ is NOT collapsed — Companies::BaseParser etc. is intentional

      # TEMPLATE.rb is a copy-paste template, not a real parser — it doesn't
      # follow Zeitwerk's one-file-one-constant convention (Companies::YourCompanyName
      # in a file named TEMPLATE.rb), so exclude it from autoloading entirely.
      Rails.autoloaders.main.ignore("#{config.root}/app/services/companies/TEMPLATE.rb")
    end

    # ---------------------------------------------------------------------------
    # TIME
    # ---------------------------------------------------------------------------
    config.time_zone = "UTC"

    # ---------------------------------------------------------------------------
    # BACKGROUND JOBS
    # ---------------------------------------------------------------------------
    # In-process async adapter — no Redis or Postgres needed for a
    # single-machine local app backed by SQLite (GoodJob requires Postgres,
    # so it isn't usable here).
    config.active_job.queue_adapter = :async

    # ---------------------------------------------------------------------------
    # ACTION CABLE
    # ---------------------------------------------------------------------------
    # Async adapter — no Redis needed for a single-machine local app
    config.action_cable.cable = { "adapter" => "async" }
  end
end
