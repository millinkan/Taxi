module Bookings
  # Creates a booking from a validated Request. The single entry point for
  # every channel, so pricing, customer matching and notifications behave the
  # same whether the booking came from the web, the phone or the voice agent.
  class Creator
    Result = Data.define(:booking, :errors, :quote) do
      def success? = errors.empty?
    end

    def initialize(tenant, actor: Actor.system, geocoder: nil, quoter: nil)
      @tenant = tenant
      @actor = actor
      @geocoder = geocoder || Geocoding::Resolver.new(tenant)
      @quoter = quoter || Pricing::Quoter.new(tenant)
    end

    def call(request)
      request.tenant = @tenant
      if (existing = replayed_booking(request))
        return Result.new(booking: existing, errors: [], quote: nil)
      end
      return failure(request.errors.full_messages) unless request.valid?

      empty_leg = find_empty_leg(request)
      return failure([ I18n.t("bookings.errors.empty_leg_gone") ]) if request.empty_leg_id && empty_leg.nil?
      if empty_leg && !(empty_leg.available_from..empty_leg.available_until).cover?(request.resolved_pickup_at)
        return failure([ I18n.t("bookings.errors.empty_leg_window") ])
      end

      pickup, dropoff = resolve_points(request, empty_leg)
      quote = price(request, pickup, dropoff, empty_leg)
      return failure([ I18n.t("bookings.errors.outside_service_area") ], quote) if quote.error == "outside_service_area"

      booking = nil
      ActiveRecord::Base.transaction do
        claim_empty_leg!(empty_leg) if empty_leg
        customer = upsert_customer(request)
        booking = @tenant.bookings.create!(booking_attributes(request, customer, pickup, dropoff, quote, empty_leg))
        customer.update!(last_booked_at: Time.current)
        booking.log!("created", actor: @actor, to_status: booking.status,
                                metadata: { source: booking.source, price_source: booking.price_source })
      end

      Lifecycle.new(booking).after_create(actor: @actor)
      Result.new(booking: booking, errors: [], quote: quote)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      existing = replayed_booking(request)
      existing ? Result.new(booking: existing, errors: [], quote: nil) : raise
    rescue EmptyLegTaken
      failure([ I18n.t("bookings.errors.empty_leg_gone") ])
    end

    class EmptyLegTaken < StandardError; end

    private
      def failure(errors, quote = nil)
        Result.new(booking: nil, errors: Array(errors), quote: quote)
      end

      # A client that retries (network blip, tool re-run) gets the booking it
      # already created instead of a second ride.
      def replayed_booking(request)
        return nil if request.idempotency_key.blank?

        @tenant.bookings.find_by(idempotency_key: request.idempotency_key)
      end

      def find_empty_leg(request)
        return nil unless request.empty_leg_id

        leg = @tenant.empty_legs.find_by(id: request.empty_leg_id)
        leg if leg&.bookable?
      end

      # Atomic check-and-set: of two customers racing for the same seat,
      # exactly one update matches the "open" row.
      def claim_empty_leg!(leg)
        claimed = @tenant.empty_legs.where(id: leg.id, status: "open")
                         .update_all(status: "booked", updated_at: Time.current)
        raise EmptyLegTaken if claimed.zero?
      end

      def resolve_points(request, empty_leg)
        return [ empty_leg.origin_point, empty_leg.destination_point ] if empty_leg

        pickup = @geocoder.resolve(request.pickup_address, lat: request.pickup_lat,
                                   lng: request.pickup_lng, place_id: request.pickup_place_id)
        dropoff = @geocoder.resolve(request.dropoff_address, lat: request.dropoff_lat,
                                    lng: request.dropoff_lng, place_id: request.dropoff_place_id)
        [ pickup || Geo::Point.new(label: request.pickup_address, lat: nil, lng: nil),
          dropoff || Geo::Point.new(label: request.dropoff_address, lat: nil, lng: nil) ]
      end

      def price(request, pickup, dropoff, empty_leg)
        if empty_leg
          return Pricing::Quote.new(price_cents: empty_leg.price_cents, currency: @tenant.currency, source: "empty_leg")
        end

        quote = @quoter.quote(pickup: pickup, dropoff: dropoff, pickup_at: request.resolved_pickup_at,
                              vehicle_category: request.category)

        # Only staff may override, and only from the dispatcher form.
        if request.manual? && request.price_override_cents
          return Pricing::Quote.new(price_cents: request.price_override_cents, currency: @tenant.currency,
                                    source: "manual", distance_m: quote.distance_m, duration_s: quote.duration_s)
        end
        # Staff can take a trip outside the usual area; the web cannot.
        return Pricing::Quote.new(currency: @tenant.currency, source: "on_request") if request.manual? && !quote.ok?

        quote
      end

      def upsert_customer(request)
        customer = @tenant.customers.find_or_initialize_by(phone: request.normalized_phone)
        customer.name = request.name if request.name.present?
        customer.email = request.email if request.email.present?
        customer.locale = request.effective_locale
        customer.save!
        customer
      end

      def booking_attributes(request, customer, pickup, dropoff, quote, empty_leg)
        outbound = request.return_of.present? ? @tenant.bookings.find_by(public_token: request.return_of) : nil
        source = request.source
        source = "return_trip" if outbound && source == "web"
        source = "empty_leg" if empty_leg && source == "web"

        {
          customer: customer,
          idempotency_key: request.idempotency_key.presence,
          source: source,
          locale: request.effective_locale,
          asap: request.asap?,
          pickup_at: request.resolved_pickup_at,
          pickup_address: pickup.label.to_s.truncate(255),
          pickup_lat: pickup.lat, pickup_lng: pickup.lng, pickup_place: pickup.place,
          dropoff_address: dropoff.label.to_s.truncate(255),
          dropoff_lat: dropoff.lat, dropoff_lng: dropoff.lng, dropoff_place: dropoff.place,
          passengers: request.passengers,
          luggage: request.luggage,
          vehicle_category: empty_leg&.vehicle_category || request.category,
          flight_number: request.flight_number.to_s.upcase.delete(" ").presence,
          notes: request.notes,
          payment_method: request.payment_method,
          quoted_price_cents: quote.price_cents,
          price_source: quote.source,
          price_estimated: quote.estimated?,
          distance_m: quote.distance_m,
          duration_s: quote.duration_s,
          outbound_booking: outbound,
          empty_leg: empty_leg,
          **request.attribution
        }
      end
  end
end
