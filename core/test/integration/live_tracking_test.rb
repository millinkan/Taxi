require "test_helper"

class LiveTrackingTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(slug: "taxi-track")
    @booking = create_booking(@tenant)
  end

  test "the customer's status page shows the live map only once the ride is confirmed" do
    get "/taxi-track/b/#{@booking.public_token}"
    assert_select "[data-controller=live-map]", 0

    Bookings::Lifecycle.new(@booking).confirm!(actor: Actor.system)
    get "/taxi-track/b/#{@booking.public_token}"
    assert_select "[data-controller=live-map]" do |map|
      channel = JSON.parse(map.first["data-live-map-channel-value"])
      assert_equal({ "channel" => "TripChannel", "public_token" => @booking.public_token }, channel)
    end
    assert_select "link[href^='/assets/leaflet-']" # served from our own host
    assert_no_match %r{cdn\.jsdelivr|unpkg\.com}, response.body
    assert_select "p", /sobald Ihr Fahrer losfährt/

    Tracking.record(@booking.reload, lat: 47.15, lng: 9.51)
    get "/taxi-track/b/#{@booking.public_token}"
    assert_select "p", /Ihr Taxi ist etwa \d+ Min\. entfernt/
  end

  test "the driver's SMS link starts sharing by itself once the ride is under way" do
    lifecycle = Bookings::Lifecycle.new(@booking)
    lifecycle.confirm!(actor: Actor.system)
    get "/d/#{@booking.dispatch_token}"
    assert_select "[data-controller=driver-tracking][data-driver-tracking-autostart-value=false]"

    lifecycle.start!(actor: Actor.system)
    get "/d/#{@booking.dispatch_token}"
    assert_select "[data-controller=driver-tracking][data-driver-tracking-autostart-value=true]"
    assert_select "[data-driver-tracking-token-value=?]", @booking.dispatch_token
  end

  test "the dispatcher's live map lists active rides with their positions" do
    Bookings::Lifecycle.new(@booking).confirm!(actor: Actor.system)
    Tracking.record(@booking.reload, lat: 47.15, lng: 9.51)

    sign_in owner_of(@tenant)
    get "/dispatch/live"
    assert_response :success
    cars = JSON.parse(css_select("[data-controller=live-map]").first["data-live-map-cars-value"])
    assert_equal [ @booking.id ], cars.pluck("booking_id")
    assert_select ".trip", 1
  end
end
