require "test_helper"

class DispatchTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(slug: "taxi-dispatch")
    @booking = create_booking(@tenant)
  end

  test "one-tap SMS link confirms without a login" do
    get "/d/#{@booking.dispatch_token}"
    assert_response :success
    assert_select "button", /Bestätigen/

    post "/d/#{@booking.dispatch_token}/confirm"
    assert @booking.reload.confirmed?
    assert_equal "dispatch_link", @booking.events.last.actor_type
    assert_equal 1, messages_for(@booking, "customer_confirmed").count
  end

  test "SMS link can start and complete a ride with a final price" do
    @booking.transition!(:confirmed)
    post "/d/#{@booking.dispatch_token}/start"
    post "/d/#{@booking.dispatch_token}/complete", params: { final_price: "295.50" }
    assert @booking.reload.completed?
    assert_equal 29_550, @booking.final_price_cents
  end

  test "a wrong token reveals nothing" do
    get "/d/not-a-real-token-at-all-xx"
    assert_response :not_found
  end

  test "staff sign in and see their board" do
    sign_in owner_of(@tenant)
    get "/dispatch"
    assert_response :success
    assert_select ".trip", minimum: 1
  end

  test "staff cannot open another firm's booking" do
    other = create_tenant(slug: "taxi-rival")
    foreign = create_booking(other)
    sign_in owner_of(@tenant)
    get "/dispatch/bookings/#{foreign.id}"
    assert_response :not_found
  end

  test "dispatcher records a phone booking and confirms it at once" do
    sign_in owner_of(@tenant)
    at = local_time(@tenant, days: 1, hour: 15)
    post "/dispatch/bookings", params: {
      confirm_now: "1",
      booking: { phone: "+4237771122", name: "Herr Frick", pickup_address: "Schaan", dropoff_address: "Bahnhof Sargans",
                 pickup_date: at.to_date.iso8601, pickup_time: "15:00", passengers: 1, luggage: 0,
                 payment_method: "in_car", locale: "de", price_override: "" }
    }
    booking = @tenant.bookings.order(:id).last
    assert_redirected_to "/dispatch/bookings/#{booking.id}"
    assert_equal "phone_manual", booking.source
    assert booking.confirmed?
  end

  test "dispatcher assigns a vehicle and the booking page shows it" do
    sign_in owner_of(@tenant)
    vehicle = @tenant.vehicles.first
    patch "/dispatch/bookings/#{@booking.id}", params: { booking: { vehicle_id: vehicle.id, internal_notes: "VIP" } }
    assert_equal vehicle, @booking.reload.vehicle

    post "/dispatch/bookings/#{@booking.id}/confirm"
    get "/dispatch/bookings/#{@booking.id}"
    assert_response :success
    assert_select "h2", /Verlauf/
  end

  test "drivers cannot change settings or see revenue" do
    driver = create_user(tenant: @tenant, role: "driver")
    sign_in driver
    get "/dashboard"
    assert_response :forbidden
    get "/settings/firm/edit"
    assert_response :forbidden
  end

  test "owner sees dashboard, settings and the Google Ads export" do
    Bookings::Lifecycle.new(@booking).confirm!(actor: Actor.system)
    sign_in owner_of(@tenant)

    get "/dashboard"
    assert_response :success
    assert_select ".hero-figure", /CHF 290/

    %w[/settings/firm/edit /settings/pricing/edit /settings/places /settings/fixed_routes /settings/vehicles
       /dispatch/calls /dispatch/empty_legs /settings/places/new /settings/fixed_routes/new /settings/vehicles/new].each do |path|
      get path
      assert_response :success, path
    end

    get "/exports/google-ads-conversions.csv"
    assert_response :success
    assert_includes response.body, "Google Click ID"
  end

  test "owner updates tariffs" do
    sign_in owner_of(@tenant)
    patch "/settings/pricing", params: { tariffs: { standard: { base_fare: "9.50", per_km: "4", per_minute: "0",
                                                                 minimum_fare: "25", rounding: "1",
                                                                 night_surcharge_percent: "25",
                                                                 night_starts_at: "23:00", night_ends_at: "05:00" } } }
    assert_redirected_to "/settings/pricing/edit"
    tariff = @tenant.tariff_for("standard")
    assert_equal 950, tariff.base_fare_cents
    assert_equal 400, tariff.per_km_cents
    assert_equal "23:00", tariff.night_starts_at
  end

  test "owner adds a fixed route and cannot use another firm's places" do
    sign_in owner_of(@tenant)
    other_place = create_tenant(slug: "taxi-third").places.first
    post "/settings/fixed_routes", params: { fixed_route: {
      origin_place_id: other_place.id, destination_place_id: place(@tenant, "Vaduz").id,
      vehicle_category: "standard", price: "50", bidirectional: "1", active: "1" } }
    assert_response :unprocessable_entity
  end
end
