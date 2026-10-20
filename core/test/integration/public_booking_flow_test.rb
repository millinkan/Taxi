require "test_helper"

class PublicBookingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(slug: "taxi-flow")
    @pickup_at = local_time(@tenant, days: 2, hour: 7)
  end

  def booking_params(**overrides)
    {
      booking: {
        pickup_address: "Vaduz", pickup_place_id: place(@tenant, "Vaduz").id,
        dropoff_address: "Flughafen Zürich", dropoff_place_id: place(@tenant, "Flughafen Zürich").id,
        pickup_date: @pickup_at.to_date.iso8601, pickup_time: "07:00",
        passengers: 2, luggage: 2, vehicle_category: "", flight_number: "LX 318",
        name: "Test Kunde", phone: "079 555 66 77", email: "", notes: "", website: ""
      }.merge(overrides)
    }
  end

  test "booking page renders in German and English" do
    get "/taxi-flow"
    assert_response :success
    assert_select "h1", /in 1 Minute gebucht/
    assert_select "button.chip", minimum: 3

    get "/taxi-flow", params: { lang: "en" }
    assert_select "h1", /booked in 1 minute/
  end

  test "live quote returns the fixed airport price" do
    get "/taxi-flow"
    post "/taxi-flow/quote", params: {
      pickup_address: "Vaduz", dropoff_address: "ZRH",
      pickup_date: @pickup_at.to_date.iso8601, pickup_time: "07:00", passengers: 2
    }, as: :json
    assert_response :success
    assert_equal 29_000, json["price_cents"]
    assert_equal "CHF 290", json["price_text"]
  end

  test "a customer books, sees the status page and can cancel" do
    get "/taxi-flow", params: { utm_source: "google", utm_campaign: "airport", gclid: "abc123" }
    post "/taxi-flow/bookings", params: booking_params

    booking = @tenant.bookings.last
    assert_redirected_to "/taxi-flow/b/#{booking.public_token}"
    assert_equal "LX318", booking.flight_number
    assert_equal "google", booking.utm_source
    assert_equal "abc123", booking.gclid

    follow_redirect!
    assert_select "h1", /#{booking.reference}/
    assert_select "a", text: /Rückfahrt buchen/

    post "/taxi-flow/b/#{booking.public_token}/cancel"
    assert booking.reload.cancelled?
    assert_equal 1, messages_for(booking, "dispatcher_cancelled").count
  end

  test "invalid input re-renders the form with errors" do
    post "/taxi-flow/bookings", params: booking_params(phone: "nope", name: "")
    assert_response :unprocessable_entity
    assert_select ".errors li", minimum: 2
    assert_equal 0, @tenant.bookings.count
  end

  test "return-trip link pre-fills the reversed route" do
    outbound = create_booking(@tenant)
    get "/taxi-flow", params: { return_of: outbound.public_token }
    assert_select "input[name='booking[pickup_address]'][value='Flughafen Zürich']"
    assert_select "input[name='booking[dropoff_address]'][value='Vaduz']"
  end

  test "status pages of another firm are not reachable" do
    other = create_tenant(slug: "taxi-other")
    foreign = create_booking(other)
    get "/taxi-flow/b/#{foreign.public_token}"
    assert_response :not_found
  end

  test "unknown or paused firms return 404" do
    get "/no-such-firm"
    assert_response :not_found

    @tenant.update!(status: "paused")
    get "/taxi-flow"
    assert_response :not_found
  end

  test "a firm's own domain serves its booking site" do
    @tenant.update!(custom_domain: "buchen.taxi-flow.li")
    host! "buchen.taxi-flow.li"
    get "/"
    assert_response :success
    assert_select "form[action='/bookings']"
  end

  test "deals page lists open empty legs" do
    booking = create_booking(@tenant)
    Bookings::Lifecycle.new(booking).confirm!(actor: Actor.system)
    get "/taxi-flow/deals"
    assert_select ".deal", 1
    assert_select ".deal", /Flughafen Zürich/
  end

  test "privacy page renders" do
    get "/taxi-flow/privacy"
    assert_response :success
    assert_select "h1", "Datenschutzerklärung"
  end
end
