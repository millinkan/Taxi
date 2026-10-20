# Operator tasks. See docs/OPERATIONS.md.
namespace :platform do
  desc "Go-live check of configuration and firm data. Exits non-zero if anything blocks go-live"
  task preflight: :environment do
    preflight = Preflight.new
    preflight.call.each do |check|
      mark = { ok: "OK  ", warn: "WARN", error: "FAIL" }.fetch(check.level)
      puts "#{mark}  #{check.label}#{"  -  #{check.detail}" if check.detail}"
    end
    abort("\n#{preflight.errors.size} blocking problem(s).") if preflight.errors.any?
    puts "\nReady to take bookings."
  end
end

namespace :users do
  desc "Create a staff user. ROLE=platform_admin|owner|dispatcher|driver TENANT=<slug> EMAIL= NAME= [PHONE=] PASSWORD="
  task create: :environment do
    role = ENV.fetch("ROLE", "dispatcher")
    tenant = role == "platform_admin" ? nil : Tenant.find_by!(slug: ENV.fetch("TENANT"))
    password = ENV["PASSWORD"].presence || SecureRandom.base58(14)

    user = User.create!(
      tenant: tenant, role: role, name: ENV.fetch("NAME"), email_address: ENV.fetch("EMAIL"),
      phone: ENV["PHONE"], password: password, locale: ENV.fetch("LOCALE", "de")
    )
    puts "Created #{user.role} #{user.email_address}#{" for #{tenant.slug}" if tenant}"
    puts "Password: #{password}" if ENV["PASSWORD"].blank?
  end

  desc "Deactivate a user and end all their sessions. EMAIL="
  task deactivate: :environment do
    user = User.find_by!(email_address: ENV.fetch("EMAIL").downcase)
    user.update!(active: false)
    user.sessions.destroy_all
    puts "Deactivated #{user.email_address}"
  end
end

namespace :tenants do
  desc "List firms with their booking page and voice number"
  task list: :environment do
    Tenant.order(:name).each do |tenant|
      puts [ tenant.slug.ljust(24), tenant.status.ljust(7), (tenant.voice_number || "-").ljust(16),
             TenantUrls.new(tenant).booking_page ].join("  ")
    end
  end
end
