# A fixed price between two places, e.g. "Liechtenstein -> Zurich Airport,
# CHF 280". Fixed prices are what customers want for long transfers and they
# take the routing provider out of the critical path.
class FixedRoute < ApplicationRecord
  include TenantOwned
  include PublishedContent

  belongs_to :origin_place, class_name: "Place"
  belongs_to :destination_place, class_name: "Place"

  validates :vehicle_category, inclusion: { in: VehicleCategory::ALL }
  validates :price_cents, numericality: { only_integer: true, greater_than: 0 }
  validate  :places_belong_to_tenant
  validate  :distinct_places

  scope :active, -> { where(active: true) }

  # Readable URL for the public route page: "12-vaduz-flughafen-zurich".
  def to_param
    "#{id}-#{"#{origin_place.name} #{destination_place.name}".parameterize(locale: :de)}" if persisted?
  end

  # All categories (standard, van, premium) priced for the same pair of places.
  def siblings
    tenant.fixed_routes.active.where(origin_place_id: origin_place_id, destination_place_id: destination_place_id)
          .order(:price_cents)
  end

  def applies_to?(pickup, dropoff)
    (origin_place.covers?(pickup) && destination_place.covers?(dropoff)) ||
      (bidirectional? && origin_place.covers?(dropoff) && destination_place.covers?(pickup))
  end

  # Smaller catchment areas are more specific and win ties.
  def specificity
    origin_place.radius_m + destination_place.radius_m
  end

  def label
    arrow = bidirectional? ? "⇄" : "→"
    "#{origin_place.name} #{arrow} #{destination_place.name}"
  end

  private
    def places_belong_to_tenant
      [ origin_place, destination_place ].compact.each do |place|
        errors.add(:base, :foreign_place) if place.tenant_id != tenant_id
      end
    end

    def distinct_places
      errors.add(:destination_place, :same_as_origin) if origin_place_id.present? && origin_place_id == destination_place_id
    end
end
