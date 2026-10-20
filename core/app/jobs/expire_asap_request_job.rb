# A "taxi now" customer is standing outside waiting. If the dispatcher has not
# answered with an ETA within the firm's response window, tell the customer
# honestly instead of letting them wait for a car that is not coming.
class ExpireAsapRequestJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking&.asap? && booking.pending?

    Bookings::Lifecycle.new(booking).expire_asap!
  rescue Booking::InvalidTransition
    # Confirmed or cancelled in the same instant: nothing to do.
  end
end
