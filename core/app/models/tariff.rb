# Metered pricing for one vehicle category. Used for any trip that does not
# match a fixed-price route.
class Tariff < ApplicationRecord
  include TenantOwned

  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d\z/

  validates :vehicle_category, inclusion: { in: VehicleCategory::ALL },
                               uniqueness: { scope: :tenant_id }
  validates :base_fare_cents, :per_km_cents, :per_minute_cents, :minimum_fare_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :night_surcharge_percent, numericality: { in: 0..200 }
  validates :rounding_cents, numericality: { only_integer: true, in: 1..1000 }
  validates :night_starts_at, :night_ends_at, format: { with: CLOCK }

  # True when the local pickup time falls in the night window. The window may
  # wrap midnight (22:00-06:00) or not (00:00-05:00).
  def night?(local_time)
    minutes = local_time.hour * 60 + local_time.min
    from = clock_minutes(night_starts_at)
    to = clock_minutes(night_ends_at)
    return false if from == to

    from < to ? minutes >= from && minutes < to : minutes >= from || minutes < to
  end

  private
    def clock_minutes(clock)
      hours, minutes = clock.split(":").map(&:to_i)
      hours * 60 + minutes
    end
end
