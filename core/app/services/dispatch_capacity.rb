# Answers "do we have a free car for this trip?" for a small fleet.
#
# Each committed booking blocks one car for a window:
#   [pickup - lead buffer, pickup + trip + way back + turnaround buffer]
# A trip that leaves the service area (e.g. Vaduz -> Zurich Airport) blocks the
# car for the drive home as well, which is exactly the dead time that empty
# legs try to sell.
class DispatchCapacity
  LEAD_BUFFER = 15.minutes
  TURNAROUND = 10.minutes
  LOCAL_RETURN = 10.minutes
  DEFAULT_TRIP = 30.minutes

  def initialize(tenant)
    @tenant = tenant
  end

  def available?(pickup_at:, duration_s:, passengers: 1, leaves_area: false, exclude_id: nil)
    fleet = @tenant.fleet_size(passengers: passengers)
    return true if fleet.zero? # no fleet configured: never auto-reject, the firm decides

    window = window_for(pickup_at, duration_s, leaves_area)
    busy = overlapping(window, exclude_id)
    busy < fleet
  end

  def window_for(pickup_at, duration_s, leaves_area)
    trip = duration_s ? duration_s.seconds : DEFAULT_TRIP
    way_back = leaves_area ? trip : LOCAL_RETURN
    (pickup_at - LEAD_BUFFER)..(pickup_at + trip + way_back + TURNAROUND)
  end

  def booking_window(booking)
    window_for(booking.pickup_at, booking.duration_s, !@tenant.within_service_area?(booking.dropoff_point))
  end

  private
    def overlapping(window, exclude_id)
      candidates = @tenant.bookings.committed
                          .where(pickup_at: (window.begin - 6.hours)..window.end)
                          .where.not(id: exclude_id)
      candidates.count { |booking| overlaps?(booking_window(booking), window) }
    end

    def overlaps?(a, b)
      a.begin < b.end && b.begin < a.end
    end
end
