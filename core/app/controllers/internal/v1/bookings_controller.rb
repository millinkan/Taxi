module Internal
  module V1
    # Creates a booking on behalf of a caller. Goes through the same
    # Bookings::Creator as the web form, so prices, SMS and dispatcher alerts
    # are identical. `idempotency_key` makes retries safe.
    class BookingsController < BaseController
      FIELDS = %i[
        pickup_address pickup_place_id dropoff_address dropoff_place_id passengers luggage
        vehicle_category flight_number notes name phone locale idempotency_key asap
      ].freeze

      def create
        with_tenant_zone do
          attrs = params.permit(*FIELDS).to_h
          attrs[:pickup_at] = parse_local_time(params[:pickup_at])
          request = Bookings::Request.new(attrs.merge(source: "voice"))
          result = Bookings::Creator.new(tenant, actor: Actor.voice_agent).call(request)

          if result.success?
            link_call(result.booking)
            render json: { ok: true, booking: booking_json(result.booking) }, status: :created
          else
            render json: { ok: false, errors: result.errors }, status: :unprocessable_entity
          end
        end
      end

      private
        def link_call(booking)
          return if params[:call_sid].blank?

          call = tenant.call_logs.find_or_initialize_by(call_sid: params[:call_sid])
          call.update!(booking: booking, customer: booking.customer, outcome: "booked",
                       started_at: call.started_at || Time.current)
        end

        def booking_json(booking)
          {
            reference: booking.reference,
            status: booking.status,
            asap: booking.asap?,
            asap_response_minutes: (tenant.asap_response_minutes if booking.asap?),
            pickup_at_local: booking.local_pickup_at.iso8601,
            pickup_address: booking.pickup_address,
            dropoff_address: booking.dropoff_address,
            price_text: format_price(booking.quoted_price_cents, tenant.currency, estimated: booking.price_estimated?),
            status_url: TenantUrls.new(tenant).status_page(booking)
          }
        end
    end
  end
end
