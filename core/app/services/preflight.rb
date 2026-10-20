# Go-live check: is this installation configured to take real bookings?
# Run on the server with `bin/kamal app exec "bin/rails platform:preflight"`.
# "error" blocks go-live; "warn" works but loses a feature or looks unfinished.
class Preflight
  Check = Data.define(:level, :label, :detail) do
    def ok? = level == :ok
  end

  PLACEHOLDER = /REPLACE|example\.(com|li|org)|localhost/i
  DEMO_SLUGS = %w[taxi-demo taxi-leo].freeze

  def initialize(env: ENV, config: Rails.configuration)
    @env = env
    @config = config
    @checks = []
  end

  def call
    platform
    messaging
    maps
    database
    firms
    @checks
  end

  def errors = @checks.select { |c| c.level == :error }

  private
    def check(condition, label, detail = nil, level: :error)
      @checks << Check.new(level: condition ? :ok : level, label: label, detail: condition ? nil : detail)
    end

    def present?(key) = @env[key].present?

    def platform
      host = @config.x.platform.host
      check(host.present? && host !~ PLACEHOLDER, "APP_HOST is the real platform host", "now #{host.inspect}")
      check(@config.x.platform.protocol == "https", "Links use https", "APP_PROTOCOL is #{@config.x.platform.protocol}")
      token = @config.x.internal_api_token.to_s
      check(token.length >= 32, "INTERNAL_API_TOKEN set (32+ characters)",
            token.empty? ? "missing: the voice agent cannot book" : "only #{token.length} characters")
      check(Rails.application.secret_key_base.present? && @env["SECRET_KEY_BASE_DUMMY"].blank?,
            "Secret key base from RAILS_MASTER_KEY", "missing: sessions and tokens are not secure")
    end

    def messaging
      check(@config.x.sms_provider == "twilio", "SMS_PROVIDER is twilio", "now #{@config.x.sms_provider}: no SMS is sent")
      check(present?("TWILIO_ACCOUNT_SID") && present?("TWILIO_AUTH_TOKEN"), "Twilio account SID and auth token",
            "missing: no SMS, and phone webhooks are rejected")
      check(present?("TWILIO_SMS_FROM") || present?("TWILIO_MESSAGING_SERVICE_SID"), "Twilio SMS sender",
            "set TWILIO_SMS_FROM or TWILIO_MESSAGING_SERVICE_SID")
      check(present?("TWILIO_WEBHOOK_BASE_URL"), "TWILIO_WEBHOOK_BASE_URL pinned",
            "recommended behind the proxy, or webhook signatures may fail", level: :warn)
      check(@config.x.email.enabled, "SMTP configured (booking emails, password resets)",
            "SMTP_ADDRESS missing: customers get SMS only, password reset emails fail", level: :warn)
      if @config.x.email.enabled
        check(@config.x.email.from !~ PLACEHOLDER, "MAIL_FROM is a real, verified sender",
              "now #{@config.x.email.from.inspect}")
      end
    end

    def maps
      check(present?("GOOGLE_MAPS_API_KEY"), "Google Maps key (exact addresses and prices)",
            "missing: street addresses are estimated, prices show \"approx.\"", level: :warn)
      if @config.x.maps.geocoder == "nominatim"
        check(@config.x.maps.contact_email !~ PLACEHOLDER, "GEOCODER_CONTACT_EMAIL is real",
              "OpenStreetMap blocks placeholder contacts")
      end
    end

    def database
      pending = ActiveRecord::Base.connection_pool.migration_context.needs_migration?
      check(!pending, "Database migrated", "run bin/rails db:migrate")
      check(User.where(role: "platform_admin", active: true).exists?, "A platform admin exists",
            "bin/rails users:create ROLE=platform_admin NAME=... EMAIL=...")
      demo = User.where("email_address LIKE ?", "%@example.com").count
      check(demo.zero?, "No demo logins", "#{demo} users with @example.com addresses: delete them or rerun without seeds")
    end

    def firms
      tenants = Tenant.active.to_a
      check(tenants.any?, "At least one active firm", "onboard the pilot firm in Admin", level: :warn)
      tenants.each do |t|
        check(!DEMO_SLUGS.include?(t.slug), "#{t.slug}: not demo data", "remove or rename the demo firm", level: :warn)
        check(t.dispatcher_phone.present?, "#{t.slug}: dispatcher mobile", "nobody is told about new bookings")
        check(t.public_phone.present?, "#{t.slug}: public phone", "customers have no number to call", level: :warn)
        check(!t.voice_agent_enabled? || t.voice_number.present?, "#{t.slug}: voice number for the AI agent",
              "voice agent switched on but no number set")
        check(t.legal_name.present? && t.licence_number.present?, "#{t.slug}: legal name and licence (imprint, emails)",
              "shown in the privacy notice and email footer", level: :warn)
        check(t.email.present?, "#{t.slug}: firm email (reply-to, privacy contact)", "customers cannot reply to emails",
              level: :warn)
      end
    end
end
