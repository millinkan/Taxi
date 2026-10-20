require "test_helper"

class BookingTest < ActiveSupport::TestCase
  setup do
    @tenant = create_tenant
    @booking = create_booking(@tenant)
  end

  test "gets a short unique reference and secret tokens" do
    assert_match(/\A[A-Z2-9]{6}\z/, @booking.reference)
    assert_equal 24, @booking.public_token.length
    assert_equal 24, @booking.dispatch_token.length
    assert_not_equal @booking.public_token, @booking.dispatch_token
  end

  test "follows the lifecycle and records who did what" do
    user = owner_of(@tenant)
    @booking.transition!(:confirmed, actor: Actor.user(user))
    @booking.transition!(:on_the_way)
    @booking.transition!(:completed, final_price_cents: 30_000)

    assert @booking.completed?
    assert_equal 30_000, @booking.revenue_cents
    assert_equal %w[created status_changed status_changed status_changed], @booking.events.map(&:action)
    assert_equal user, @booking.events.second.actor_user
  end

  test "refuses impossible transitions" do
    assert_raises(Booking::InvalidTransition) { @booking.transition!(:completed) }
    @booking.transition!(:declined)
    assert_raises(Booking::InvalidTransition) { @booking.transition!(:confirmed) }
  end

  test "customers can cancel only until the cut-off" do
    assert @booking.customer_cancellable?
    travel_to @booking.pickup_at - 1.hour
    assert_not @booking.customer_cancellable?
  end

  test "a booking cannot point at another firm's customer" do
    other = create_tenant
    foreign = other.customers.create!(phone: "+41790000000")
    @booking.customer = foreign
    assert_not @booking.valid?
  end
end
