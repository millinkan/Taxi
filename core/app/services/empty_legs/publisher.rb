module EmptyLegs
  # When a long one-way trip is confirmed (Vaduz -> Zurich Airport), the car
  # will drive home empty. We publish that return as a discounted ride on the
  # firm's booking page, so the dead kilometres can earn money.
  #
  # Privacy: the published leg never contains the customer's address. It runs
  # from the drop-off *place* (e.g. "Zurich Airport") back to the firm's home
  # area, and is only created when the drop-off is a named place.
  class Publisher
    WAIT_AFTER_ARRIVAL = 10.minutes
    WINDOW = 90.minutes
    PRICE_STEP_CENTS = 500

    def initialize(booking)
      @booking = booking
      @tenant = booking.tenant
    end

    def publish
      return unless eligible?

      @tenant.empty_legs.create!(
        source_booking: @booking,
        origin_label: @booking.dropoff_place.name,
        origin_lat: @booking.dropoff_place.lat,
        origin_lng: @booking.dropoff_place.lng,
        destination_label: @tenant.home_area_label,
        destination_lat: @tenant.service_center_lat,
        destination_lng: @tenant.service_center_lng,
        available_from: arrival,
        available_until: arrival + WINDOW,
        regular_price_cents: @booking.quoted_price_cents,
        price_cents: discounted_price,
        vehicle_category: @booking.vehicle_category,
        seats: seats
      )
    end

    def eligible?
      @tenant.empty_legs_enabled? &&
        @booking.source != "empty_leg" &&
        @booking.dropoff_place.present? &&
        @tenant.service_center.present? &&
        @booking.quoted_price_cents.to_i.positive? &&
        @booking.distance_m.to_i >= @tenant.empty_leg_min_distance_km * 1000 &&
        !@tenant.within_service_area?(@booking.dropoff_point) &&
        @booking.empty_legs_created.none?
    end

    private
      def arrival
        @booking.pickup_at + (@booking.duration_s || 3600).seconds + WAIT_AFTER_ARRIVAL
      end

      def discounted_price
        raw = @booking.quoted_price_cents * (100 - @tenant.empty_leg_discount_percent) / 100.0
        [ (raw / PRICE_STEP_CENTS).floor * PRICE_STEP_CENTS, PRICE_STEP_CENTS ].max
      end

      def seats
        @booking.vehicle&.seats || VehicleCategory::DEFAULT_SEATS.fetch(@booking.vehicle_category, 4)
      end
  end
end
