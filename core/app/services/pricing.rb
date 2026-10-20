# Computes the price of a trip. The single source of truth for prices: the web
# form, the voice agent and the dispatcher all call this, and a booking always
# stores the server-side quote, never a price sent by a client.
#
# Order of precedence:
#   1. a fixed-price route covering both ends (airport transfers, etc.)
#   2. the metered tariff for the vehicle category (+ night surcharge)
#   3. "on request" when we cannot locate an address; the firm prices it
module Pricing
  class Quote
    attr_reader :price_cents, :currency, :source, :distance_m, :duration_s,
                :fixed_route, :night, :error, :breakdown

    def initialize(price_cents: nil, currency:, source:, estimated: false, distance_m: nil,
                   duration_s: nil, fixed_route: nil, night: false, error: nil, breakdown: {})
      @price_cents = price_cents
      @currency = currency
      @source = source
      @estimated = estimated
      @distance_m = distance_m
      @duration_s = duration_s
      @fixed_route = fixed_route
      @night = night
      @error = error
      @breakdown = breakdown
    end

    def ok? = error.nil?
    def priced? = ok? && price_cents.present?
    def estimated? = @estimated
    def on_request? = source == "on_request"

    def as_json(*)
      {
        ok: ok?, error: error, price_cents: price_cents, currency: currency, source: source,
        estimated: estimated?, distance_km: distance_m && (distance_m / 1000.0).round(1),
        duration_min: duration_s && (duration_s / 60.0).round, night: night,
        fixed_route: fixed_route&.label
      }
    end
  end

  class Quoter
    def initialize(tenant, router: Routing)
      @tenant = tenant
      @router = router
    end

    # pickup / dropoff are Geo::Points (possibly without coordinates).
    def quote(pickup:, dropoff:, pickup_at:, vehicle_category: "standard")
      category = VehicleCategory.valid?(vehicle_category) ? vehicle_category : "standard"

      unless pickup&.located? && dropoff&.located?
        return build(source: "on_request")
      end

      unless @tenant.within_service_area?(pickup) || @tenant.within_service_area?(dropoff)
        return build(source: "on_request", error: "outside_service_area")
      end

      route = @router.route(pickup, dropoff)

      if (fixed = fixed_route_for(pickup, dropoff, category))
        return build(price_cents: fixed.price_cents, source: "fixed_route", fixed_route: fixed,
                     distance_m: route&.distance_m, duration_s: route&.duration_s,
                     breakdown: { fixed_route: fixed.label })
      end

      tariff = @tenant.tariff_for(category)
      return build(source: "on_request", distance_m: route&.distance_m, duration_s: route&.duration_s) unless tariff && route

      metered(tariff, route, pickup_at)
    end

    private
      def fixed_route_for(pickup, dropoff, category)
        @tenant.fixed_routes.active.where(vehicle_category: category)
               .includes(:origin_place, :destination_place)
               .select { |route| route.applies_to?(pickup, dropoff) }
               .min_by(&:specificity)
      end

      def metered(tariff, route, pickup_at)
        km = route.distance_m / 1000.0
        minutes = route.duration_s / 60.0
        base = tariff.base_fare_cents + tariff.per_km_cents * km + tariff.per_minute_cents * minutes
        night = tariff.night?(pickup_at.in_time_zone(@tenant.time_zone))
        surcharge = night ? base * tariff.night_surcharge_percent / 100.0 : 0
        subtotal = [ base + surcharge, tariff.minimum_fare_cents ].max
        price = round_to(subtotal, tariff.rounding_cents)

        build(price_cents: price, source: "tariff", estimated: route.estimated,
              distance_m: route.distance_m, duration_s: route.duration_s, night: night,
              breakdown: {
                base_fare_cents: tariff.base_fare_cents, km: km.round(1), minutes: minutes.round,
                night_surcharge_cents: surcharge.round, minimum_fare_cents: tariff.minimum_fare_cents
              })
      end

      def round_to(cents, step)
        ((cents / step.to_f).round * step).to_i
      end

      def build(**attrs)
        Quote.new(currency: @tenant.currency, **attrs)
      end
  end
end
