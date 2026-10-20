# One ride's live position.
#
#   driver:   subscribe with dispatch_token  -> may send positions (#update)
#   customer: subscribe with public_token    -> receives positions, read-only
#
# Both tokens are the same 24-character secrets already used in the SMS links,
# so tracking grants nothing a link holder could not already see.
class TripChannel < ApplicationCable::Channel
  def subscribed
    if (booking = Booking.find_by(dispatch_token: params[:dispatch_token].to_s.presence))
      # Kept for the whole ride: each position then costs one UPDATE, no reads.
      @driver_booking = booking
    elsif (booking = Booking.find_by(public_token: params[:public_token].to_s.presence))
      return reject unless booking.trackable?
    else
      return reject
    end

    stream_from Tracking.trip_stream(booking)
    if (position = Tracking.position(booking))
      transmit(position)
    end
  end

  # From the driver's phone: { lat, lng, heading, accuracy }.
  def update(data)
    return unless @driver_booking

    result = Tracking.record(@driver_booking, lat: data["lat"], lng: data["lng"],
                                              heading: data["heading"], accuracy: data["accuracy"])
    transmit({ ended: true }) if result == :not_trackable
  end
end
