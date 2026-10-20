require "test_helper"

class SupportServicesTest < ActiveSupport::TestCase
  test "Twilio signature matches Twilio's documented example" do
    # Example from Twilio's "Webhooks security" documentation.
    url = "https://mycompany.com/myapp.php?foo=1&bar=2"
    params = { "CallSid" => "CA1234567890ABCDE", "Caller" => "+12349013030", "Digits" => "1234",
               "From" => "+12349013030", "To" => "+18005551212" }
    signature = TwilioSignature.compute(url: url, params: params, auth_token: "12345")

    assert_equal "0/KCTR6DLpKmkAf8muzZqo1nDgQ=", signature
    assert TwilioSignature.valid?(url: url, params: params, signature: signature, auth_token: "12345")
    assert_not TwilioSignature.valid?(url: url, params: params, signature: "forged", auth_token: "12345")
  end

  test "capacity treats out-of-area trips as blocking the car for the way back" do
    tenant = create_tenant(vehicles: 1)
    booking = create_booking(tenant, pickup_at: local_time(tenant, days: 2, hour: 6))
    booking.transition!(:confirmed)
    capacity = DispatchCapacity.new(tenant)

    window = capacity.booking_window(booking)
    assert_operator window.end - booking.pickup_at, :>, 2 * booking.duration_s
    assert_not capacity.available?(pickup_at: booking.pickup_at + booking.duration_s.seconds, duration_s: 900)
    assert capacity.available?(pickup_at: window.end + 20.minutes, duration_s: 900)
  end

  test "missed-call text-back is sent once per caller per day" do
    tenant = create_tenant
    2.times do |i|
      call = tenant.call_logs.create!(call_sid: "CA#{i}", from_number: "+41795550000", outcome: "abandoned")
      CallFollowUp.new(call).perform
    end
    assert_equal 1, tenant.message_logs.where(purpose: "missed_call_textback").count
  end

  test "data retention anonymises inactive customers and wipes transcripts" do
    tenant = create_tenant
    tenant.update!(data_retention_days: 30)
    booking = create_booking(tenant)
    call = tenant.call_logs.create!(call_sid: "CAold", from_number: "+41795550000",
                                    transcript: [ { "role" => "caller", "text" => "hi" } ])

    travel 40.days
    DataRetentionJob.perform_now

    assert booking.customer.reload.anonymized_at
    assert_nil booking.customer.name
    assert_equal [], call.reload.transcript
    assert booking.reload.persisted?
  end

  test "onboarding creates a working firm from the regional template" do
    tenant = create_tenant
    assert_equal 3, tenant.tariffs.count
    assert_operator tenant.places.count, :>=, 20
    assert_operator tenant.fixed_routes.count, :>=, 20
    assert_equal "Europe/Vaduz", tenant.time_zone
    assert owner_of(tenant).owner?
  end

  test "performance report separates platform revenue" do
    tenant = create_tenant
    web = create_booking(tenant)
    phone = create_booking(tenant, source: "phone_manual", phone: "+41790000009")
    [ web, phone ].each { |b| Bookings::Lifecycle.new(b).confirm!(actor: Actor.system) }

    report = PerformanceReport.new(tenant, "30d")
    assert_equal 2, report.total_bookings
    assert_equal 58_000, report.revenue_cents
    assert_equal 29_000, report.platform_revenue_cents
  end
end
