require "test_helper"

# "Taxi now": the customer at the bar. No lead time, the dispatcher answers
# with an ETA, and nobody is left waiting for a car that is not coming.
class TaxiNowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(slug: "taxi-now")
  end

  def now_params(**overrides)
    {
      booking: {
        asap: "1", pickup_address: "Bar Sonne, Vaduz", pickup_lat: "47.141000", pickup_lng: "9.521000",
        dropoff_address: "Schaan", passengers: 2, name: "Nacht Gast", phone: "079 555 66 77", notes: "", website: ""
      }.merge(overrides)
    }
  end

  test "the taxi-now page renders and pre-fills from a link" do
    get "/taxi-now/now", params: { pickup: "Hotel Real", dropoff: "Schaan", lat: "47.14", lng: "9.52", pax: 3 }
    assert_response :success
    assert_select "h1", /Taxi sofort/
    assert_select "input[name='booking[asap]'][value='1']"
    assert_select "input[name='booking[pickup_address]'][value='Hotel Real']"
    assert_select "input[name='booking[pickup_lat]'][value='47.14']"
    assert_select "select[name='booking[passengers]'] option[selected][value='3']"
  end

  test "the booking page points to taxi now" do
    get "/taxi-now"
    assert_select "a.now-banner[href='/taxi-now/now']"
  end

  test "a taxi-now request skips the lead time and alerts the dispatcher" do
    assert_enqueued_with(job: ExpireAsapRequestJob) do
      post "/taxi-now/bookings", params: now_params
    end

    booking = @tenant.bookings.sole
    assert_redirected_to "/taxi-now/b/#{booking.public_token}"
    assert booking.asap?
    assert booking.pending?
    assert_in_delta Time.current, booking.pickup_at, 5.seconds
    assert_equal 47.141, booking.pickup_lat.to_f

    assert_match(/\ATAXI SOFORT: Bar Sonne/, messages_for(booking, "dispatcher_new_booking").sole.body)
    assert_match(/innert 3 Min/, messages_for(booking, "customer_received").sole.body)

    follow_redirect!
    assert_select "meta[http-equiv=refresh]"
    assert_select "p", /Wir suchen ein freies Fahrzeug/
  end

  test "the dispatcher answers with an ETA from the SMS link" do
    post "/taxi-now/bookings", params: now_params
    booking = @tenant.bookings.sole

    get "/d/#{booking.dispatch_token}"
    assert_select "form[action='/d/#{booking.dispatch_token}/confirm'] input[name=eta][value='10']"

    post "/d/#{booking.dispatch_token}/confirm", params: { eta: 10 }
    booking.reload
    assert booking.confirmed?
    assert_equal 10, booking.eta_minutes
    assert_in_delta 10.minutes.from_now, booking.pickup_at, 5.seconds
    assert_match(/Ankunft in ca\. 10 Min\./, messages_for(booking, "customer_confirmed").sole.body)

    # A late expiry job changes nothing once a car is promised.
    perform_enqueued_jobs(only: ExpireAsapRequestJob)
    assert booking.reload.confirmed?
  end

  test "nobody answers in time: the customer is told straight away" do
    post "/taxi-now/bookings", params: now_params
    booking = @tenant.bookings.sole

    travel 3.minutes do
      perform_enqueued_jobs(only: ExpireAsapRequestJob)
    end

    booking.reload
    assert booking.declined?
    assert_equal "no_response", booking.cancellation_reason
    assert_match(/kein Fahrzeug frei/, messages_for(booking, "customer_asap_unavailable").sole.body)
    assert_equal 1, messages_for(booking, "dispatcher_asap_missed").count

    get "/taxi-now/b/#{booking.public_token}"
    assert_select "a[href='/taxi-now/now']"
  end

  test "the customer can withdraw a request until a car is promised" do
    post "/taxi-now/bookings", params: now_params
    booking = @tenant.bookings.sole

    post "/taxi-now/b/#{booking.public_token}/cancel"
    assert booking.reload.cancelled?
  end

  test "taxi-now requests come first on the board with ETA buttons" do
    create_booking(@tenant)
    post "/taxi-now/bookings", params: now_params
    asap = @tenant.bookings.find_by!(asap: true)

    sign_in owner_of(@tenant)
    get "/dispatch"
    assert_select ".trip--asap", 1
    assert_select ".card .trip:first-child.trip--asap"

    get "/dispatch/bookings/#{asap.id}"
    assert_select ".eta-grid form", Bookings::Lifecycle::ETA_CHOICES.size

    post "/dispatch/bookings/#{asap.id}/confirm", params: { eta: 15 }
    assert_equal 15, asap.reload.eta_minutes
  end

  test "firms can switch taxi now off" do
    @tenant.update!(asap_enabled: false)

    get "/taxi-now/now"
    assert_redirected_to "/taxi-now"

    post "/taxi-now/bookings", params: now_params
    assert_response :unprocessable_entity
    assert_equal 0, @tenant.bookings.count
  end

  test "the phone assistant can place a taxi-now request" do
    post "/internal/v1/bookings", params: {
      tenant_id: @tenant.id, pickup_address: "Vaduz", dropoff_address: "Schaan", pickup_at: "2026-10-19T10:00",
      passengers: 1, name: "Anrufer", phone: "+41795551234", locale: "de", asap: true, idempotency_key: "toolu_now"
    }, headers: internal_headers, as: :json

    assert_response :created
    assert json.dig("booking", "asap")
    assert_equal 3, json.dig("booking", "asap_response_minutes")
    assert @tenant.bookings.sole.asap?

    post "/internal/v1/quotes", params: {
      tenant_id: @tenant.id, pickup_address: "Vaduz", dropoff_address: "Schaan", pickup_at: "2026-10-19T10:05", passengers: 1
    }, headers: internal_headers, as: :json
    assert_equal false, json["lead_time_ok"]
    assert_equal true, json["asap_available"]
  end
end
