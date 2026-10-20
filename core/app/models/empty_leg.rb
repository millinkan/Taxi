# A discounted seat on a car that would otherwise drive home empty, e.g. the
# return from Zurich Airport after a drop-off. Selling these turns dead
# kilometres into revenue.
class EmptyLeg < ApplicationRecord
  include TenantOwned
  include PublishedContent

  STATUSES = %w[open booked expired withdrawn].freeze

  belongs_to :source_booking, class_name: "Booking", optional: true
  has_one :booking, dependent: :nullify

  validates :origin_label, :destination_label, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :vehicle_category, inclusion: { in: VehicleCategory::ALL }
  validate  :window_is_ordered

  scope :listed, -> { where(status: "open") }
  scope :bookable, -> { listed.where(available_until: Time.current..).order(:available_from) }

  def bookable? = status == "open" && available_until > Time.current

  def savings_cents
    regular_price_cents.to_i - price_cents if regular_price_cents.to_i > price_cents
  end

  def origin_point
    Geo::Point.new(label: origin_label, lat: origin_lat, lng: origin_lng)
  end

  def destination_point
    Geo::Point.new(label: destination_label, lat: destination_lat, lng: destination_lng)
  end

  private
    def window_is_ordered
      return unless available_from && available_until

      errors.add(:available_until, :before_start) if available_until <= available_from
    end
end
