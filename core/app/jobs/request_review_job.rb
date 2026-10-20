# Reviews drive Google Maps ranking, which drives free inbound calls. Ask
# every happy customer once, an hour after the ride.
class RequestReviewJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking&.completed? && booking.review_requested_at.nil?
    return if booking.customer.anonymized_at
    # Ask each customer at most once every 90 days.
    return if booking.customer.bookings.where(review_requested_at: 90.days.ago..).exists?

    Notifier.new(booking).customer_review_request
  end
end
