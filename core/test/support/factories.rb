# Small, explicit builders instead of YAML fixtures: each test says what it
# needs. Firms are built through TenantOnboarding with the real Liechtenstein
# template, so tests exercise the same data a pilot firm gets.
module Factories
  PASSWORD = "correct-horse-battery".freeze

  def create_tenant(slug: "taxi-#{SecureRandom.hex(3)}", region: "liechtenstein", vehicles: 4, **attrs)
    result = TenantOnboarding.new(
      tenant_attrs: {
        name: "Taxi #{slug}", slug: slug, dispatcher_phone: "+41791234567",
        public_phone: "+4232300000", google_review_url: "https://g.page/r/review"
      }.merge(attrs),
      owner_attrs: { name: "Owner", email_address: "owner-#{slug}@example.com", password: PASSWORD },
      region: region
    ).call
    raise "tenant factory failed: #{result.errors.to_sentence}" unless result.success?

    tenant = result.tenant
    vehicles.times { |i| tenant.vehicles.create!(name: "Car #{i + 1}", category: "standard", seats: 4) }
    tenant
  end

  def owner_of(tenant) = tenant.users.find_by!(role: "owner")

  def create_user(tenant:, role: "dispatcher", email: "user-#{SecureRandom.hex(3)}@example.com")
    User.create!(tenant: tenant, role: role, name: role.titleize, email_address: email, password: PASSWORD)
  end

  def create_platform_admin
    User.create!(role: "platform_admin", name: "Admin", email_address: "admin-#{SecureRandom.hex(3)}@example.com",
                 password: PASSWORD)
  end

  def place(tenant, name) = tenant.places.find_by!(name: name)

  # Local wall-clock time in the firm's zone, n days from "now".
  def local_time(tenant, days: 1, hour: 10, min: 0)
    Time.find_zone(tenant.time_zone).now.advance(days: days).change(hour: hour, min: min)
  end

  def booking_request(tenant, **overrides)
    pickup_at = overrides.delete(:pickup_at) || local_time(tenant)
    Bookings::Request.new({
      source: "web", locale: "de", name: "Anna Muster", phone: "079 555 66 77",
      pickup_address: "Vaduz", dropoff_address: "Flughafen Zürich",
      pickup_date: pickup_at.to_date.iso8601, pickup_time: pickup_at.strftime("%H:%M"),
      passengers: 2, luggage: 1
    }.merge(overrides))
  end

  def create_booking(tenant, **overrides)
    result = Bookings::Creator.new(tenant).call(booking_request(tenant, **overrides))
    raise "booking factory failed: #{result.errors.to_sentence}" unless result.success?

    result.booking
  end

  def messages_for(booking, purpose)
    booking.tenant.message_logs.where(booking: booking, purpose: purpose)
  end
end
