# Central place for every environment variable the platform reads.
# Documented in docs/CONFIGURATION.md; keep the two in sync.
Rails.application.configure do
  google_key = ENV["GOOGLE_MAPS_API_KEY"].presence

  config.x.platform.name     = ENV.fetch("PLATFORM_NAME", "RideDesk")
  config.x.platform.host     = ENV.fetch("APP_HOST", "localhost:3000")
  config.x.platform.protocol = ENV.fetch("APP_PROTOCOL", Rails.env.production? ? "https" : "http")

  # Shared secret for the voice service -> core internal API.
  config.x.internal_api_token = ENV["INTERNAL_API_TOKEN"].presence

  config.x.twilio.account_sid           = ENV["TWILIO_ACCOUNT_SID"].presence
  config.x.twilio.auth_token            = ENV["TWILIO_AUTH_TOKEN"].presence
  config.x.twilio.sms_from              = ENV["TWILIO_SMS_FROM"].presence
  config.x.twilio.messaging_service_sid = ENV["TWILIO_MESSAGING_SERVICE_SID"].presence
  # Twilio signs webhooks against the public URL; behind a proxy the request
  # URL Rails sees can differ, so the public base URL can be pinned here.
  config.x.twilio.webhook_base_url      = ENV["TWILIO_WEBHOOK_BASE_URL"].presence

  config.x.sms_provider =
    if Rails.env.test? then "test"
    else ENV.fetch("SMS_PROVIDER", Rails.env.production? ? "twilio" : "log")
    end

  # Booking emails to customers. Production sends them only once SMTP is set
  # up (config/environments/production.rb); until then customers get SMS only.
  config.x.email.from = ENV.fetch("MAIL_FROM", "bookings@#{config.x.platform.host.split(":").first}")
  config.x.email.enabled = Rails.env.production? ? ENV["SMTP_ADDRESS"].present? : true

  config.x.maps.api_key = google_key
  config.x.maps.osrm_url = ENV["OSRM_URL"].presence
  config.x.maps.geocoder =
    if Rails.env.test? then "null"
    else ENV.fetch("GEOCODER", google_key ? "google" : "nominatim")
    end
  config.x.maps.routing =
    if Rails.env.test? then "estimate"
    else ENV.fetch("ROUTING", google_key ? "google" : (ENV["OSRM_URL"].present? ? "osrm" : "estimate"))
    end
  config.x.maps.contact_email = ENV.fetch("GEOCODER_CONTACT_EMAIL", "ops@example.com")

  # Search engine / AI discovery (docs/DISCOVERY.md).
  config.x.discovery.indexnow_key = ENV["INDEXNOW_KEY"].presence
  config.x.discovery.google_service_account = ENV["GOOGLE_SERVICE_ACCOUNT_JSON"].presence
  config.x.discovery.google_site = ENV["GOOGLE_SEARCH_CONSOLE_SITE"].presence
  config.x.discovery.auto_push =
    !Rails.env.test? && ActiveModel::Type::Boolean.new.cast(ENV.fetch("DISCOVERY_AUTO_PUSH", "true"))
end
