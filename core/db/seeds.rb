# Development / demo data. Idempotent: safe to run more than once.
#
#   bin/rails db:seed
#
# Creates a platform admin and a demo firm onboarded through the same
# TenantOnboarding service used in production, plus a few sample bookings so
# the board and dashboard have something to show.
# Production: do NOT seed. Create the admin with `bin/rails users:create`.

abort "Refusing to seed demo data in production." if Rails.env.production?

admin_password = ENV.fetch("SEED_PASSWORD", "change-me-please")

User.find_or_create_by!(email_address: "admin@example.com") do |user|
  user.name = "Platform Admin"
  user.role = "platform_admin"
  user.password = admin_password
end

tenant = Tenant.find_by(slug: "taxi-demo")
unless tenant
  result = TenantOnboarding.new(
    tenant_attrs: {
      name: "Taxi Demo Vaduz",
      slug: "taxi-demo",
      legal_name: "Taxi Demo AG",
      licence_number: "FL-TX-0001",
      public_phone: "+4232300000",
      dispatcher_name: "Demo Dispatcher",
      dispatcher_phone: "+41791234567",
      voice_number: "+41445550000",
      email: "info@taxi-demo.example",
      google_review_url: "https://g.page/r/demo-review",
      voice_agent_enabled: true
    },
    owner_attrs: { name: "Demo Owner", email_address: "owner@example.com", password: admin_password },
    region: "liechtenstein"
  ).call
  abort("Seeding failed: #{result.errors.to_sentence}") unless result.success?
  tenant = result.tenant

  [ [ "Mercedes E 220", "FL 1001", "standard", 4 ],
    [ "Skoda Superb", "FL 1002", "standard", 4 ],
    [ "VW Passat", "FL 1003", "standard", 4 ],
    [ "Mercedes V-Klasse", "FL 1004", "van", 8 ] ].each do |name, plate, category, seats|
    tenant.vehicles.create!(name: name, plate: plate, category: category, seats: seats)
  end
end

if tenant.bookings.none?
  Time.use_zone(tenant.time_zone) do
    samples = [
      { name: "Anna Beck", phone: "+41791110001", pickup_address: "Vaduz", dropoff_address: "Flughafen Zürich",
        pickup_at: 2.days.from_now.change(hour: 6, min: 15), passengers: 2, luggage: 2, flight_number: "LX1612" },
      { name: "Marco Frick", phone: "+4237771122", pickup_address: "Schaan", dropoff_address: "Bahnhof Sargans",
        pickup_at: 1.day.from_now.change(hour: 9, min: 0), passengers: 1, source: "phone_manual" },
      { name: "Sarah Keller", phone: "+436641234567", pickup_address: "Flughafen Zürich", dropoff_address: "Vaduz",
        pickup_at: 3.days.from_now.change(hour: 18, min: 40), passengers: 3, luggage: 3, flight_number: "LH1190" }
    ]
    samples.each do |attrs|
      request = Bookings::Request.new({ source: "web", locale: "de" }.merge(attrs))
      result = Bookings::Creator.new(tenant).call(request)
      puts "  sample booking: #{result.success? ? result.booking.reference : result.errors.to_sentence}"
    end
  end
end

# Pilot prospect, modelled on their public booking page (taxileo.li): their
# name, public number and fleet. Prices come from the regional template and
# must be confirmed with the firm. The dispatcher and voice numbers are
# placeholders so testing never texts or rings the firm's real phone.
leo = Tenant.find_by(slug: "taxi-leo")
unless leo
  result = TenantOnboarding.new(
    tenant_attrs: {
      name: "Taxi Leo",
      slug: "taxi-leo",
      public_phone: "+41786000007",
      website_url: "https://www.taxileo.li",
      dispatcher_name: "Taxi Leo Disposition",
      dispatcher_phone: "+41791234568",
      voice_number: "+41445550001",
      voice_agent_enabled: true
    },
    owner_attrs: { name: "Leo (Demo)", email_address: "leo@example.com", password: admin_password },
    region: "liechtenstein"
  ).call
  abort("Seeding Taxi Leo failed: #{result.errors.to_sentence}") unless result.success?
  leo = result.tenant

  [ [ "Mercedes-Benz S-Klasse", "premium", 4 ],
    [ "Mercedes-Benz V-Klasse XL", "van", 6 ],
    [ "VW Passat", "standard", 4 ],
    [ "Cadillac Stretchlimousine", "premium", 8 ] ].each do |name, category, seats|
    leo.vehicles.create!(name: name, category: category, seats: seats)
  end
end

if leo.bookings.none?
  Time.use_zone(leo.time_zone) do
    [ { name: "Lukas Büchel", phone: "+41791110011", email: "lukas@example.com", pickup_address: "Vaduz",
        dropoff_address: "Flughafen Zürich", pickup_at: 2.days.from_now.change(hour: 7, min: 0), passengers: 2,
        luggage: 2, vehicle_category: "premium", flight_number: "LX318" },
      { name: "Petra Wohlwend", phone: "+41791110012", email: "petra@example.com", pickup_address: "Schaan",
        dropoff_address: "Davos", pickup_at: 4.days.from_now.change(hour: 15, min: 30), passengers: 6, luggage: 6,
        vehicle_category: "van" } ].each do |attrs|
      request = Bookings::Request.new({ source: "web", locale: "de" }.merge(attrs))
      result = Bookings::Creator.new(leo).call(request)
      puts "  Taxi Leo booking: #{result.success? ? result.booking.reference : result.errors.to_sentence}"
    end
  end
end

puts <<~TEXT

  Seeded.
    Platform admin : admin@example.com / #{admin_password}
    Firm owner     : owner@example.com / #{admin_password}
    Booking page   : #{TenantUrls.new(tenant).booking_page}
    Taxi Leo owner : leo@example.com / #{admin_password}
    Taxi Leo page  : #{TenantUrls.new(leo).booking_page}
TEXT
