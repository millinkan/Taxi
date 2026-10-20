module Public
  class BookingsController < BaseController
    PERMITTED = %i[
      pickup_address pickup_place_id pickup_lat pickup_lng
      dropoff_address dropoff_place_id dropoff_lat dropoff_lng
      pickup_date pickup_time passengers luggage vehicle_category flight_number notes
      name phone email empty_leg_id return_of website asap
    ].freeze

    rate_limit to: 10, within: 10.minutes, only: :create,
               with: -> { redirect_to site_path(:booking_page), alert: t("public.rate_limited") }

    def new
      @request = prefilled_request
      load_page_data
    end

    def create
      @request = Bookings::Request.new(booking_params)
      result = Bookings::Creator.new(current_tenant).call(@request)

      if result.success?
        session.delete(:attribution)
        redirect_to site_path(:booking_status, token: result.booking.public_token), notice: t("public.booking.created")
      else
        @errors = result.errors
        load_page_data
        render(@request.asap? ? "public/now/show" : :new, status: :unprocessable_entity)
      end
    end

    def show
      @booking = current_tenant.bookings.includes(:customer, :return_booking).find_by!(public_token: params[:token])
    end

    def cancel
      booking = current_tenant.bookings.find_by!(public_token: params[:token])
      if booking.customer_cancellable?
        Bookings::Lifecycle.new(booking).cancel!(actor: Actor.customer(booking.customer), reason: "customer")
        redirect_to site_path(:booking_status, token: booking.public_token), notice: t("public.booking.cancelled")
      else
        redirect_to site_path(:booking_status, token: booking.public_token), alert: t("public.booking.cannot_cancel")
      end
    end

    private
      def booking_params
        attrs = params.require(:booking).permit(*PERMITTED).to_h
        attribution = (session[:attribution] || {}).slice("utm_source", "utm_medium", "utm_campaign", "gclid",
                                                          "landing_page", "referrer")
        attrs.merge(attribution).merge(source: "web", locale: I18n.locale.to_s)
      end

      def load_page_data
        @places = current_tenant.featured_places.to_a
        @deals = current_tenant.empty_legs.bookable.limit(3).to_a
        @route_pages = Discovery::Profile.new(current_tenant).route_pages.first(12)
        @localities = Discovery::Localities.new(current_tenant)
      end

      # Links can pre-fill the form: ?from=<place id>&to=<place id>,
      # ?return_of=<booking token> for a return trip, ?deal=<empty leg id>.
      def prefilled_request
        request = Bookings::Request.new(pickup_date: Date.current.iso8601)
        if (from = current_tenant.places.find_by(id: params[:from]))
          request.pickup_address = from.name
          request.pickup_place_id = from.id
        end
        if (to = current_tenant.places.find_by(id: params[:to]))
          request.dropoff_address = to.name
          request.dropoff_place_id = to.id
        end
        prefill_return(request) if params[:return_of].present?
        prefill_deal(request) if params[:deal].present?
        request
      end

      def prefill_return(request)
        outbound = current_tenant.bookings.find_by(public_token: params[:return_of])
        return unless outbound

        request.return_of = outbound.public_token
        request.pickup_address = outbound.dropoff_address
        request.pickup_place_id = outbound.dropoff_place_id
        request.dropoff_address = outbound.pickup_address
        request.dropoff_place_id = outbound.pickup_place_id
        request.passengers = outbound.passengers
        request.name = outbound.customer.name
        request.phone = outbound.customer.phone
      end

      def prefill_deal(request)
        leg = current_tenant.empty_legs.bookable.find_by(id: params[:deal])
        return unless leg

        @deal = leg
        request.empty_leg_id = leg.id
        request.pickup_address = leg.origin_label
        request.dropoff_address = leg.destination_label
        local = leg.available_from.in_time_zone(current_tenant.time_zone)
        request.pickup_date = local.to_date.iso8601
        request.pickup_time = local.strftime("%H:%M")
      end
  end
end
