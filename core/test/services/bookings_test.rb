require "test_helper"

class BookingsTest < ActiveSupport::TestCase
  setup { @tenant = create_tenant }

  test "a web booking is priced on the server, stored pending and both sides are told" do
    booking = create_booking(@tenant)

    assert booking.pending?
    assert_equal 29_000, booking.quoted_price_cents
    assert_equal "fixed_route", booking.price_source
    assert_equal "+41795556677", booking.customer.phone
    assert_equal "Flughafen Zürich", booking.dropoff_place.name
    assert_equal 1, messages_for(booking, "dispatcher_new_booking").count
    assert_equal 1, messages_for(booking, "customer_received").count
    assert_enqueued_with(job: EscalatePendingBookingJob, args: [ booking.id ])
  end

  test "dispatcher SMS contains the one-tap link and stays in the GSM-7 alphabet" do
    booking = create_booking(@tenant)
    body = messages_for(booking, "dispatcher_new_booking").first.body

    assert_includes body, "/d/#{booking.dispatch_token}"
    assert_includes body, "CHF 290"
    gsm7 = "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
    assert body.chars.all? { |c| gsm7.include?(c) }, "non-GSM-7 characters in: #{body}"
    assert_no_match(/translation missing/i, body)
  end

  test "returning customers are recognised by phone number" do
    first = create_booking(@tenant)
    second = create_booking(@tenant, phone: "+41 79 555 66 77", pickup_at: local_time(@tenant, days: 5))
    assert_equal first.customer, second.customer
    assert_equal 2, second.customer.reload.bookings_count
  end

  test "rejects bookings that are too soon, spam, or have a bad phone number" do
    too_soon = booking_request(@tenant, pickup_at: Time.current + 5.minutes)
    assert_not Bookings::Creator.new(@tenant).call(too_soon).success?

    spam = booking_request(@tenant, website: "http://spam.example")
    assert_not Bookings::Creator.new(@tenant).call(spam).success?

    bad_phone = booking_request(@tenant, phone: "call me")
    assert_not Bookings::Creator.new(@tenant).call(bad_phone).success?

    assert_equal 0, @tenant.bookings.count
  end

  test "the same idempotency key never creates a second ride" do
    request = -> { booking_request(@tenant, source: "voice", idempotency_key: "toolu_123") }
    first = Bookings::Creator.new(@tenant).call(request.call)
    again = Bookings::Creator.new(@tenant).call(request.call)

    assert_equal first.booking, again.booking
    assert_equal 1, @tenant.bookings.count
  end

  test "dispatcher may override the price on a phone booking, the web may not" do
    manual = Bookings::Creator.new(@tenant).call(booking_request(@tenant, source: "phone_manual", price_override: "250"))
    assert_equal 25_000, manual.booking.quoted_price_cents
    assert_equal "manual", manual.booking.price_source

    web = Bookings::Creator.new(@tenant).call(booking_request(@tenant, price_override: "1", pickup_at: local_time(@tenant, days: 2)))
    assert_equal 29_000, web.booking.quoted_price_cents
  end

  test "auto-confirms when enabled, far enough ahead and a car is free" do
    @tenant.update!(auto_confirm: true, auto_confirm_min_lead_hours: 6)
    booking = create_booking(@tenant)

    assert booking.reload.confirmed?
    assert_equal 1, messages_for(booking, "customer_confirmed").count
    assert_equal 1, messages_for(booking, "dispatcher_new_booking").count
    assert_equal 0, messages_for(booking, "customer_received").count
  end

  test "does not auto-confirm when the fleet is fully booked" do
    tenant = create_tenant(vehicles: 1)
    tenant.update!(auto_confirm: true)
    at = local_time(tenant, days: 2, hour: 9)
    create_booking(tenant, pickup_at: at)
    second = create_booking(tenant, pickup_at: at + 30.minutes, phone: "+41790000001")

    assert second.reload.pending?
  end

  test "confirming a long trip to the airport publishes an empty leg back home" do
    booking = create_booking(@tenant)
    Bookings::Lifecycle.new(booking).confirm!(actor: Actor.system)

    leg = @tenant.empty_legs.sole
    assert_equal "Flughafen Zürich", leg.origin_label
    assert_equal "Liechtenstein", leg.destination_label
    assert_equal 17_000, leg.price_cents # 290 less 40 %, floored to CHF 5
    assert_operator leg.available_from, :>, booking.pickup_at
    assert_not_includes [ leg.origin_label, leg.destination_label ], booking.pickup_address
  end

  test "an empty leg can be sold exactly once" do
    origin = create_booking(@tenant)
    Bookings::Lifecycle.new(origin).confirm!(actor: Actor.system)
    leg = @tenant.empty_legs.sole
    at = leg.available_from.in_time_zone(@tenant.time_zone) + 10.minutes

    first = Bookings::Creator.new(@tenant).call(booking_request(@tenant, empty_leg_id: leg.id, pickup_at: at, phone: "+41790000002"))
    second = Bookings::Creator.new(@tenant).call(booking_request(@tenant, empty_leg_id: leg.id, pickup_at: at, phone: "+41790000003"))

    assert first.success?
    assert_equal "empty_leg", first.booking.source
    assert_equal 17_000, first.booking.quoted_price_cents
    assert_not second.success?
    assert_equal "booked", leg.reload.status
  end

  test "cancelling an empty-leg booking puts the seat back on sale" do
    origin = create_booking(@tenant)
    Bookings::Lifecycle.new(origin).confirm!(actor: Actor.system)
    leg = @tenant.empty_legs.sole
    at = leg.available_from.in_time_zone(@tenant.time_zone) + 10.minutes
    sold = create_booking(@tenant, empty_leg_id: leg.id, pickup_at: at, phone: "+41790000004")

    Bookings::Lifecycle.new(sold).cancel!(actor: Actor.customer(sold.customer))
    assert_equal "open", leg.reload.status
  end

  test "a return trip links to its outbound ride" do
    outbound = create_booking(@tenant)
    back = create_booking(@tenant, return_of: outbound.public_token, pickup_address: "Flughafen Zürich",
                                   dropoff_address: "Vaduz", pickup_at: local_time(@tenant, days: 8))
    assert_equal "return_trip", back.source
    assert_equal outbound, back.outbound_booking
  end

  test "escalation reminds the dispatcher once if still pending" do
    booking = create_booking(@tenant)
    EscalatePendingBookingJob.perform_now(booking.id)
    EscalatePendingBookingJob.perform_now(booking.id)
    assert_equal 1, messages_for(booking, "dispatcher_reminder").count
  end

  test "completed rides trigger one review request" do
    booking = create_booking(@tenant)
    lifecycle = Bookings::Lifecycle.new(booking)
    lifecycle.confirm!(actor: Actor.system)
    lifecycle.complete!(actor: Actor.system, final_price_cents: 29_500)
    RequestReviewJob.perform_now(booking.id)
    RequestReviewJob.perform_now(booking.id)

    assert_equal 29_500, booking.reload.final_price_cents
    assert_equal 1, messages_for(booking, "customer_review_request").count
  end
end
