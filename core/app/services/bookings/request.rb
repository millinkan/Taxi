module Bookings
  # Everything needed to create a booking, from any channel: the public web
  # form, the dispatcher's phone-booking form, or the voice agent's API call.
  # Validation of *input* lives here; persistence rules live on Booking.
  class Request
    include ActiveModel::Model
    include ActiveModel::Attributes

    MANUAL_BACKDATE_LIMIT = 12.hours

    attr_accessor :tenant

    attribute :source, :string, default: "web"
    attribute :locale, :string

    attribute :pickup_address, :string
    attribute :pickup_lat, :float
    attribute :pickup_lng, :float
    attribute :pickup_place_id, :integer
    attribute :dropoff_address, :string
    attribute :dropoff_lat, :float
    attribute :dropoff_lng, :float
    attribute :dropoff_place_id, :integer

    # "Taxi now": no pickup time and no lead time; the dispatcher answers with an ETA.
    attribute :asap, :boolean, default: false
    attribute :pickup_at, :datetime
    attribute :pickup_date, :string
    attribute :pickup_time, :string

    attribute :passengers, :integer, default: 1
    attribute :luggage, :integer, default: 0
    attribute :vehicle_category, :string
    attribute :flight_number, :string
    attribute :notes, :string
    attribute :payment_method, :string, default: "in_car"

    attribute :name, :string
    attribute :phone, :string
    attribute :email, :string

    attribute :idempotency_key, :string
    attribute :empty_leg_id, :integer
    attribute :return_of, :string
    attribute :price_override, :decimal
    attribute :website, :string # honeypot: real people never fill this in

    attribute :utm_source, :string
    attribute :utm_medium, :string
    attribute :utm_campaign, :string
    attribute :gclid, :string
    attribute :landing_page, :string
    attribute :referrer, :string

    validates :name, presence: true, length: { maximum: 80 }
    validates :phone, presence: true
    validates :passengers, numericality: { only_integer: true, in: 1..16 }
    validates :luggage, numericality: { only_integer: true, in: 0..20 }
    validates :source, inclusion: { in: Booking::SOURCES }
    validates :payment_method, inclusion: { in: Booking::PAYMENT_METHODS }
    validates :vehicle_category, inclusion: { in: VehicleCategory::ALL }, allow_blank: true
    validates :flight_number, format: { with: /\A[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?\z/i }, allow_blank: true
    validates :pickup_address, :dropoff_address, presence: true, unless: :empty_leg_id
    validates :notes, length: { maximum: 500 }
    validate  :phone_is_valid
    validate  :pickup_time_is_valid
    validate  :honeypot_is_empty

    def manual? = source == "phone_manual"
    def asap? = asap == true

    def normalized_phone
      PhoneNumber.normalize(phone)
    end

    def category
      vehicle_category.presence || VehicleCategory.for_passengers(passengers)
    end

    def effective_locale
      locale.presence_in(Tenant::LOCALES) || tenant&.default_locale || "de"
    end

    # The pickup time as an absolute instant, interpreted in the firm's zone.
    def resolved_pickup_at
      return @resolved_pickup_at if defined?(@resolved_pickup_at)

      zone = ActiveSupport::TimeZone[tenant&.time_zone || "Europe/Vaduz"]
      @resolved_pickup_at =
        if asap?
          Time.current.in_time_zone(zone)
        elsif pickup_at.present?
          pickup_at.in_time_zone(zone)
        elsif pickup_date.present? && pickup_time.present?
          zone.parse("#{pickup_date} #{pickup_time}")
        end
    rescue ArgumentError
      @resolved_pickup_at = nil
    end

    def price_override_cents
      (price_override * 100).round if price_override.present?
    end

    def attribution
      {
        utm_source: utm_source, utm_medium: utm_medium, utm_campaign: utm_campaign,
        gclid: gclid, landing_page: landing_page, referrer: referrer
      }.transform_values { |value| value.to_s.truncate(255).presence }
    end

    private
      def phone_is_valid
        errors.add(:phone, :invalid) if phone.present? && normalized_phone.nil?
      end

      def pickup_time_is_valid
        return errors.add(:base, :asap_unavailable) if asap? && tenant && !tenant.asap_enabled?
        return if asap?

        time = resolved_pickup_at
        return errors.add(:pickup_at, :blank) if time.nil?
        return unless tenant

        earliest = manual? ? Time.current - MANUAL_BACKDATE_LIMIT : Time.current + tenant.min_lead_minutes.minutes
        latest = Time.current + tenant.max_advance_days.days
        if time < earliest
          errors.add(:pickup_at, :too_soon, minutes: tenant.min_lead_minutes)
        elsif time > latest
          errors.add(:pickup_at, :too_far, days: tenant.max_advance_days)
        end
      end

      def honeypot_is_empty
        errors.add(:base, :spam) if website.present?
      end
  end
end
