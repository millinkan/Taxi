require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Core
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks action_cable])
    # Action Cable requires pubsub adapters by path (config/cable.yml), so our
    # own adapter in lib/action_cable/ must be on the load path, not autoloaded.
    $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Store everything in UTC; each firm's own time zone is applied for display
    # and for interpreting the pickup times customers type.
    config.time_zone = "UTC"

    config.i18n.available_locales = %i[de en]
    config.i18n.default_locale = :de
    config.i18n.fallbacks = [ :en ]
  end
end
