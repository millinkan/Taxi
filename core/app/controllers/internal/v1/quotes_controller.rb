module Internal
  module V1
    # Price, resolved addresses and availability for a trip the caller
    # describes. The voice agent reads `price_text` and the resolved labels
    # back to the caller before booking.
    class QuotesController < BaseController
      def create
        with_tenant_zone do
          geocoder = Geocoding::Resolver.new(tenant)
          pickup = geocoder.resolve(params[:pickup_address], place_id: params[:pickup_place_id])
          dropoff = geocoder.resolve(params[:dropoff_address], place_id: params[:dropoff_place_id])
          pickup_at = parse_local_time(params[:pickup_at])
          return render(json: { ok: false, error: "invalid_pickup_at" }, status: :unprocessable_entity) unless pickup_at

          passengers = params[:passengers].to_i.clamp(1, 16)
          category = params[:vehicle_category].presence_in(VehicleCategory::ALL) || VehicleCategory.for_passengers(passengers)
          quote = Pricing::Quoter.new(tenant).quote(pickup: pickup, dropoff: dropoff, pickup_at: pickup_at,
                                                    vehicle_category: category)

          render json: {
            ok: quote.ok?,
            error: quote.error,
            price_cents: quote.price_cents,
            price_text: quote.priced? ? format_price(quote.price_cents, tenant.currency, estimated: quote.estimated?) : nil,
            price_source: quote.source,
            estimated: quote.estimated?,
            vehicle_category: category,
            distance_km: quote.as_json[:distance_km],
            duration_min: quote.as_json[:duration_min],
            pickup: { label: pickup&.label, located: pickup&.located? || false },
            dropoff: { label: dropoff&.label, located: dropoff&.located? || false },
            pickup_at_local: pickup_at.iso8601,
            lead_time_ok: pickup_at >= tenant.min_lead_minutes.minutes.from_now,
            asap_available: tenant.asap_enabled?,
            capacity_available: DispatchCapacity.new(tenant).available?(
              pickup_at: pickup_at, duration_s: quote.duration_s, passengers: passengers,
              leaves_area: dropoff.present? && !tenant.within_service_area?(dropoff)
            )
          }
        end
      end
    end
  end
end
