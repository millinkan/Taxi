class Booking < ApplicationRecord
  include TenantOwned

  STATUSES = %w[pending confirmed on_the_way completed cancelled declined no_show].freeze
  OPEN_STATUSES = %w[pending confirmed on_the_way].freeze
  COMMITTED_STATUSES = %w[confirmed on_the_way].freeze
  TRANSITIONS = {
    "pending"    => %w[confirmed declined cancelled],
    "confirmed"  => %w[on_the_way completed cancelled no_show],
    "on_the_way" => %w[completed cancelled no_show]
  }.freeze

  # Where the booking came from. "Platform" sources are the ones the firm
  # would not have had without us; the dashboard reports them separately.
  SOURCES = %w[web voice phone_manual return_trip empty_leg api].freeze
  PLATFORM_SOURCES = %w[web voice return_trip empty_leg].freeze
  PAYMENT_METHODS = %w[in_car invoice].freeze
  PRICE_SOURCES = %w[fixed_route tariff manual empty_leg on_request].freeze
  REFERENCE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze

  # Raised when someone asks for a status change the lifecycle does not allow.
  class InvalidTransition < StandardError; end

  belongs_to :customer, counter_cache: true
  belongs_to :pickup_place, class_name: "Place", optional: true
  belongs_to :dropoff_place, class_name: "Place", optional: true
  belongs_to :driver, class_name: "User", optional: true
  belongs_to :vehicle, optional: true
  belongs_to :outbound_booking, class_name: "Booking", optional: true
  belongs_to :empty_leg, optional: true
  has_one  :return_booking, class_name: "Booking", foreign_key: :outbound_booking_id, dependent: :nullify
  has_many :events, -> { order(:created_at, :id) }, class_name: "BookingEvent", dependent: :delete_all
  has_many :message_logs, dependent: :nullify
  has_many :call_logs, dependent: :nullify
  has_many :empty_legs_created, class_name: "EmptyLeg", foreign_key: :source_booking_id, dependent: :nullify

  has_secure_token :public_token, length: 24
  has_secure_token :dispatch_token, length: 24

  before_validation :assign_reference, on: :create

  validates :reference, presence: true, uniqueness: { scope: :tenant_id }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :price_source, inclusion: { in: PRICE_SOURCES }, allow_nil: true
  validates :vehicle_category, inclusion: { in: VehicleCategory::ALL }
  validates :locale, inclusion: { in: Tenant::LOCALES }
  validates :pickup_at, :pickup_address, :dropoff_address, presence: true
  validates :passengers, numericality: { only_integer: true, in: 1..16 }
  validates :luggage, numericality: { only_integer: true, in: 0..20 }
  validates :quoted_price_cents, :final_price_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :flight_number, format: { with: /\A[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?\z/i }, allow_blank: true
  validate  :customer_belongs_to_tenant

  scope :unfinished, -> { where(status: OPEN_STATUSES) }
  scope :committed, -> { where(status: COMMITTED_STATUSES) }
  scope :completed, -> { where(status: "completed") }
  scope :pending, -> { where(status: "pending") }
  scope :upcoming, -> { unfinished.where(pickup_at: 2.hours.ago..).order(:pickup_at) }
  scope :from_platform, -> { where(source: PLATFORM_SOURCES) }
  scope :picked_up_between, ->(range) { where(pickup_at: range) }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  def open? = status.in?(OPEN_STATUSES)
  # Live tracking runs from confirmation until the ride ends.
  def trackable? = status.in?(COMMITTED_STATUSES)
  def committed? = status.in?(COMMITTED_STATUSES)

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(status, []).include?(new_status.to_s)
  end

  # Moves the booking along its lifecycle and records who did it. Side
  # effects (SMS, empty legs) live in Bookings::Lifecycle, not here.
  def transition!(new_status, actor: Actor.system, reason: nil, final_price_cents: nil)
    new_status = new_status.to_s
    raise InvalidTransition, "#{status} -> #{new_status}" unless can_transition_to?(new_status)

    previous = status
    transaction do
      self.status = new_status
      stamp_for(new_status, reason: reason, final_price_cents: final_price_cents)
      save!
      log!("status_changed", actor: actor, from_status: previous, to_status: new_status,
                             metadata: { reason: reason }.compact)
    end
    self
  end

  def log!(action, actor: Actor.system, from_status: nil, to_status: nil, metadata: {})
    events.create!(tenant: tenant, action: action, from_status: from_status, to_status: to_status,
                   actor_type: actor.type, actor_id: actor.id, metadata: metadata)
  end

  # The figure that counts as revenue: what was charged, else what was quoted.
  def revenue_cents
    final_price_cents || quoted_price_cents || 0
  end

  def price_known? = quoted_price_cents.present?

  def local_pickup_at
    pickup_at.in_time_zone(tenant.time_zone)
  end

  def minutes_until_pickup
    ((pickup_at - Time.current) / 60).round
  end

  def pickup_point
    Geo::Point.new(label: pickup_address, lat: pickup_lat, lng: pickup_lng, place: pickup_place)
  end

  def dropoff_point
    Geo::Point.new(label: dropoff_address, lat: dropoff_lat, lng: dropoff_lng, place: dropoff_place)
  end

  def to_airport? = dropoff_place&.airport? || false
  def from_airport? = pickup_place&.airport? || false

  # Customers can cancel themselves until the firm's cut-off.
  # A "taxi now" request can be withdrawn until a car is promised.
  def customer_cancellable?
    return pending? if asap?

    open? && !on_the_way? && pickup_at > tenant.free_cancellation_hours.hours.from_now
  end

  def navigation_url(point = pickup_point)
    query = point.located? ? "#{point.lat},#{point.lng}" : point.label
    "https://www.google.com/maps/dir/?api=1&destination=#{ERB::Util.url_encode(query)}"
  end

  private
    def assign_reference
      return if reference.present?

      10.times do
        candidate = Array.new(6) { REFERENCE_ALPHABET.sample(random: SecureRandom) }.join
        unless Booking.where(tenant_id: tenant_id, reference: candidate).exists?
          self.reference = candidate
          return
        end
      end
      raise "could not allocate a unique booking reference"
    end

    def stamp_for(new_status, reason:, final_price_cents:)
      now = Time.current
      case new_status
      when "confirmed"  then self.confirmed_at = now
      when "on_the_way" then self.started_at = now
      when "completed"
        self.completed_at = now
        self.final_price_cents = final_price_cents if final_price_cents
      when "cancelled", "declined", "no_show"
        self.cancelled_at = now
        self.cancellation_reason = reason
      end
    end

    def customer_belongs_to_tenant
      errors.add(:customer, :invalid) if customer && customer.tenant_id != tenant_id
    end
end
