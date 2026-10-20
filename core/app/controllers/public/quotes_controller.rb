module Public
  # Live price shown while the customer fills in the form. Purely
  # informational: the booking re-quotes on the server when it is created.
  class QuotesController < BaseController
    include PriceFormatting

    rate_limit to: 40, within: 1.minute, with: -> { render json: { ok: false, error: "rate_limited" }, status: :too_many_requests }

    def create
      geocoder = Geocoding::Resolver.new(current_tenant)
      pickup = geocoder.resolve(params[:pickup_address], place_id: params[:pickup_place_id],
                                lat: params[:pickup_lat], lng: params[:pickup_lng])
      dropoff = geocoder.resolve(params[:dropoff_address], place_id: params[:dropoff_place_id],
                                 lat: params[:dropoff_lat], lng: params[:dropoff_lng])
      pickup_at = parse_pickup_at
      category = params[:vehicle_category].presence || VehicleCategory.for_passengers(params[:passengers])

      quote = Pricing::Quoter.new(current_tenant).quote(pickup: pickup, dropoff: dropoff,
                                                         pickup_at: pickup_at, vehicle_category: category)
      render json: quote.as_json.merge(
        price_text: quote.priced? ? format_price(quote.price_cents, current_tenant.currency, estimated: quote.estimated?) : nil,
        pickup_label: pickup&.label, dropoff_label: dropoff&.label,
        message: quote_message(quote)
      )
    end

    private
      def parse_pickup_at
        Time.zone.parse("#{params[:pickup_date]} #{params[:pickup_time]}") || Time.current
      rescue ArgumentError
        Time.current
      end

      def quote_message(quote)
        if quote.error == "outside_service_area" then t("public.quote.outside_area")
        elsif quote.on_request? then t("public.quote.on_request")
        elsif quote.estimated? then t("public.quote.estimated")
        elsif quote.source == "fixed_route" then t("public.quote.fixed")
        end
      end
  end
end
