require "test_helper"

class TripChannelTest < ActionCable::Channel::TestCase
  setup do
    @tenant = create_tenant(slug: "taxi-live")
    @booking = create_booking(@tenant)
    Bookings::Lifecycle.new(@booking).confirm!(actor: Actor.system)
    stub_connection current_user: nil
  end

  def stream = "trip:#{@booking.id}"
  def point(**extra) = { "lat" => 47.1500, "lng" => 9.5100, "heading" => 182.6, "accuracy" => 12 }.merge(extra)

  test "the driver streams the car's position to the ride and the fleet" do
    subscribe dispatch_token: @booking.dispatch_token
    assert subscription.confirmed?
    assert_has_stream stream

    assert_broadcasts("fleet:#{@tenant.id}", 1) do
      assert_broadcasts(stream, 1) { perform :update, point }
    end

    @booking.reload
    assert_equal 47.15, @booking.driver_lat.to_f
    assert_equal 183, @booking.driver_heading
    position = Tracking.position(@booking)
    assert position[:distance_m].positive?
    assert position[:eta_min] >= 1
  end

  test "the customer watches read-only and gets the last known position on joining" do
    Tracking.record(@booking, lat: 47.15, lng: 9.51)

    subscribe public_token: @booking.public_token
    assert subscription.confirmed?
    assert_equal 47.15, transmissions.last["lat"]

    assert_no_broadcasts(stream) { perform :update, point(lat: 47.2) }
    assert_equal 47.15, @booking.reload.driver_lat.to_f
  end

  test "nothing is visible before confirmation or without a valid token" do
    pending = create_booking(@tenant)
    subscribe public_token: pending.public_token
    assert subscription.rejected?

    subscribe public_token: "not-a-token"
    assert subscription.rejected?

    subscribe
    assert subscription.rejected?
  end

  test "bursts are throttled and imprecise fixes dropped" do
    subscribe dispatch_token: @booking.dispatch_token

    assert_broadcasts(stream, 1) do
      perform :update, point
      perform :update, point(lat: 47.151)
    end
    travel Tracking::MIN_INTERVAL
    assert_no_broadcasts(stream) { perform :update, point(accuracy: 900) }
    assert_broadcasts(stream, 1) { perform :update, point(lat: 47.152) }
  end

  test "each position costs one UPDATE and no reads" do
    subscribe dispatch_token: @booking.dispatch_token
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { perform :update, point }

    assert_equal 1, queries.size, queries.inspect
    assert_match(/\AUPDATE "bookings"/, queries.first)
  end

  test "the position is forgotten the moment the ride ends" do
    subscribe dispatch_token: @booking.dispatch_token
    perform :update, point

    assert_broadcast_on(stream, { booking_id: @booking.id, ended: true, status: "completed" }) do
      Bookings::Lifecycle.new(@booking.reload).complete!(actor: Actor.system)
    end
    @booking.reload
    assert_nil @booking.driver_lat
    assert_nil @booking.driver_located_at

    perform :update, point
    assert_equal true, transmissions.last["ended"]
    assert_nil @booking.reload.driver_lat
  end
end
