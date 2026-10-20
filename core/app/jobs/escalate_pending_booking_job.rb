# A booking nobody has confirmed is a booking about to be lost. If the
# dispatcher has not reacted after the firm's escalation delay, nudge again.
class EscalatePendingBookingJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking&.pending? && booking.escalated_at.nil?

    Notifier.new(booking).dispatcher_reminder
    booking.update_column(:escalated_at, Time.current)
    booking.log!("escalated")
  end
end
