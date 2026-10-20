require "test_helper"

class PreflightTest < ActiveSupport::TestCase
  READY_ENV = {
    "TWILIO_ACCOUNT_SID" => "AC123", "TWILIO_AUTH_TOKEN" => "secret", "TWILIO_SMS_FROM" => "TaxiLeo",
    "TWILIO_WEBHOOK_BASE_URL" => "https://app.ridedesk.li", "GOOGLE_MAPS_API_KEY" => "key"
  }.freeze

  setup { create_platform_admin }

  test "a fully configured installation is ready" do
    create_tenant(slug: "taxi-vaduz", legal_name: "Taxi Vaduz AG", licence_number: "FL-1", email: "info@taxi.li")
    User.update_all("email_address = replace(email_address, '@example.com', '@ridedesk.li')")

    preflight = Preflight.new(env: READY_ENV, config: config)
    checks = preflight.call

    assert_empty preflight.errors, preflight.errors.map(&:label).to_sentence
    assert checks.all?(&:ok?), checks.reject(&:ok?).map(&:label).to_sentence
  end

  test "placeholders and missing secrets block go-live" do
    create_tenant(slug: "taxi-demo")
    preflight = Preflight.new(env: {}, config: config(host: "app.REPLACE-DOMAIN.li", token: nil, sms: "log"))
    preflight.call
    blocking = preflight.errors.map(&:label)

    assert_includes blocking, "APP_HOST is the real platform host"
    assert_includes blocking, "INTERNAL_API_TOKEN set (32+ characters)"
    assert_includes blocking, "SMS_PROVIDER is twilio"
    assert_includes blocking, "Twilio account SID and auth token"
    assert_includes blocking, "No demo logins"
    assert_not_includes blocking, "taxi-demo: not demo data", "demo firm is a warning, not a blocker"
  end

  private
    def options(hash) = ActiveSupport::OrderedOptions.new.update(hash)

    def config(host: "app.ridedesk.li", token: "t" * 40, sms: "twilio")
      x = options(
        platform: options(host: host, protocol: "https"),
        internal_api_token: token,
        sms_provider: sms,
        email: options(enabled: true, from: "bookings@ridedesk.li"),
        maps: options(geocoder: "google", contact_email: "ops@ridedesk.li")
      )
      Struct.new(:x).new(x)
    end
end
