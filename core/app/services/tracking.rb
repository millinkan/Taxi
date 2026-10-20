# Live position of the car on an active ride, streamed over WebSockets
# (ActionCable; in production Solid Cable plus in-process fast delivery, see
# lib/action_cable/subscription_adapter/local_first.rb).
#
#   driver phone ──position──► TripChannel ──► Tracking.record
#                                              ├─► "trip:<booking>"   customer's status page
#                                              └─► "fleet:<tenant>"   dispatcher's live map
#
# Hot path: one indexed UPDATE (which also enforces status and throttle),
# then two broadcasts built from values already in memory. No reads.
#
# Privacy by design: only the latest point is stored, only while the ride is
# confirmed or under way, and it is deleted the moment the ride ends.
module Tracking
  # The server accepts at most one point per ride this often; the phone
  # already sends only on movement, this is the backstop.
  MIN_INTERVAL = 1.second
  # Points less precise than this (indoors, cell-tower fixes) are dropped.
  MAX_ACCURACY_M = 250
  # Straight-line distance to road distance, and average town speed, for the
  # live "about 4 min away" estimate. Deliberately simple: no routing call
  # per position update.
  ROAD_FACTOR = 1.3
  AVERAGE_KMH = 35.0

  module_function

  def trip_stream(booking) = "trip:#{booking.id}"
  def fleet_stream(tenant_or_id) = "fleet:#{tenant_or_id.is_a?(Integer) ? tenant_or_id : tenant_or_id.id}"

  # Returns :ok, :not_trackable, :invalid or :throttled. `booking` may be a
  # copy loaded earlier (the channel keeps one): the UPDATE decides, not it.
  def record(booking, lat:, lng:, heading: nil, accuracy: nil)
    lat = Float(lat, exception: false)
    lng = Float(lng, exception: false)
    return :invalid unless lat && lng && lat.between?(-90, 90) && lng.between?(-180, 180)
    return :invalid if accuracy && Float(accuracy, exception: false).to_f > MAX_ACCURACY_M

    now = Time.current
    heading = heading_degrees(heading)
    # Atomic: still active, and of two points racing in only one wins the interval.
    updated = Booking.where(id: booking.id, status: Booking::COMMITTED_STATUSES)
                     .where("driver_located_at IS NULL OR driver_located_at <= ?", now - MIN_INTERVAL)
                     .update_all(driver_lat: lat, driver_lng: lng, driver_heading: heading,
                                 driver_located_at: now, updated_at: now)
    if updated.zero?
      return Booking.where(id: booking.id, status: Booking::COMMITTED_STATUSES).exists? ? :throttled : :not_trackable
    end

    booking.driver_lat = lat
    booking.driver_lng = lng
    booking.driver_heading = heading
    booking.driver_located_at = now
    broadcast(booking, position(booking))
    :ok
  end

  # The ride is over (completed, cancelled, no-show): forget the position and
  # tell every open map to stop.
  def stop(booking)
    # Decided in the database: the in-memory copy may predate the last point.
    Booking.where(id: booking.id).where.not(driver_located_at: nil)
           .update_all(driver_lat: nil, driver_lng: nil, driver_heading: nil, driver_located_at: nil)
    booking.assign_attributes(driver_lat: nil, driver_lng: nil, driver_heading: nil, driver_located_at: nil)
    booking.clear_attribute_changes(%i[driver_lat driver_lng driver_heading driver_located_at])
    broadcast(booking, { booking_id: booking.id, ended: true, status: booking.status })
  end

  def position(booking)
    return nil unless booking.driver_located_at

    distance = (distance_to_pickup_m(booking) if booking.pickup_lat && booking.pickup_lng)
    {
      booking_id: booking.id,
      reference: booking.reference,
      lat: booking.driver_lat.to_f,
      lng: booking.driver_lng.to_f,
      heading: booking.driver_heading,
      at: booking.driver_located_at.iso8601(3),
      distance_m: distance&.round,
      eta_min: distance && [ (distance * ROAD_FACTOR / 1000.0 / AVERAGE_KMH * 60).ceil, 1 ].max
    }.compact
  end

  def distance_to_pickup_m(booking)
    Geo.distance_m(booking.driver_lat.to_f, booking.driver_lng.to_f, booking.pickup_lat.to_f, booking.pickup_lng.to_f)
  end

  def broadcast(booking, payload)
    ActionCable.server.broadcast(trip_stream(booking), payload)
    ActionCable.server.broadcast(fleet_stream(booking.tenant_id), payload)
  end

  def heading_degrees(heading)
    value = Float(heading, exception: false)
    value.round % 360 if value
  end
end
