class Tenant < ApplicationRecord
  STATUSES = %w[active paused].freeze
  LOCALES = %w[de en].freeze

  # Slugs share the URL namespace with the application's own routes.
  RESERVED_SLUGS = %w[
    admin api assets b d dashboard dispatch exports internal login logout
    passwords rails session settings twilio up cable manifest service-worker
  ].freeze

  # Settings that show on public pages, in the schema.org markup, llms.txt or
  # the discovery feed; changing one triggers a search-engine push.
  PUBLISHED_ATTRIBUTES = %w[
    name slug legal_name licence_number status currency default_locale logo_url public_phone email
    website_url custom_domain dispatcher_phone service_center_lat service_center_lng service_radius_km
    home_area_label min_lead_minutes max_advance_days asap_enabled asap_response_minutes opening_hours
    google_business_url empty_legs_enabled
  ].freeze

  include PublishedContent

  has_many :users, dependent: :destroy
  has_many :vehicles, dependent: :destroy
  has_many :tariffs, dependent: :destroy
  has_many :places, dependent: :destroy
  has_many :fixed_routes, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :booking_events, dependent: :delete_all
  has_many :call_logs, dependent: :destroy
  has_many :message_logs, dependent: :delete_all
  has_many :empty_legs, dependent: :destroy
  has_many :discovery_pushes, dependent: :delete_all

  normalizes :slug, with: ->(s) { s.to_s.strip.downcase }
  normalizes :custom_domain, with: ->(d) { d.to_s.strip.downcase.presence }
  normalizes :dispatcher_phone, :public_phone, :voice_number,
             with: ->(p) { PhoneNumber.normalize(p) || p.to_s.strip.presence }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ },
                   exclusion: { in: RESERVED_SLUGS }
  validates :status, inclusion: { in: STATUSES }
  validates :default_locale, inclusion: { in: LOCALES }
  validates :currency, inclusion: { in: %w[CHF EUR] }
  validates :brand_color, format: { with: /\A#\h{6}\z/ }
  validates :custom_domain, uniqueness: true, allow_nil: true
  validates :voice_number, uniqueness: true, allow_nil: true
  validates :dispatcher_phone, :public_phone, :voice_number,
            format: { with: PhoneNumber::E164, message: :invalid_phone }, allow_blank: true
  validates :sms_sender_id, format: { with: /\A[A-Za-z0-9 ]{1,11}\z/ }, allow_blank: true
  validates :service_radius_km, numericality: { greater_than: 0, less_than_or_equal_to: 300 }
  validates :empty_leg_discount_percent, numericality: { in: 0..90 }
  validates :asap_response_minutes, numericality: { only_integer: true, in: 1..30 }
  validates :opening_hours, presence: true, length: { maximum: 120 }
  validates :google_business_url, format: { with: %r{\Ahttps://\S+\z} }, allow_blank: true
  validate  :time_zone_exists

  scope :active, -> { where(status: "active") }

  def self.for_host(host)
    active.find_by(custom_domain: host.to_s.downcase) if host.present?
  end

  def self.for_voice_number(number)
    find_by(voice_number: PhoneNumber.normalize(number))
  end

  def active? = status == "active"

  def service_center
    return nil unless service_center_lat && service_center_lng

    Geo::Point.new(label: name, lat: service_center_lat, lng: service_center_lng)
  end

  def within_service_area?(point)
    return true unless service_center && point&.located?

    Geo.point_distance_m(service_center, point) <= service_radius_km * 1000
  end

  def tariff_for(category)
    tariffs.find_by(vehicle_category: category) || tariffs.find_by(vehicle_category: "standard")
  end

  def now
    Time.current.in_time_zone(time_zone)
  end

  def featured_places
    places.where(featured: true).order(:position, :name)
  end

  # Capacity in vehicles that can carry at least this many passengers.
  def fleet_size(passengers: 1)
    vehicles.where(active: true).where("seats >= ?", passengers).count
  end

  private
    def publishing_tenant = self
    def published_change? = !destroyed? && saved_changes.keys.intersect?(PUBLISHED_ATTRIBUTES)

    def time_zone_exists
      errors.add(:time_zone, :invalid) unless ActiveSupport::TimeZone[time_zone.to_s]
    end
end
