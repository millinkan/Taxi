module Public
  # "Taxi now": the page Google, AI assistants and the booking page send
  # someone to who needs a car right away. It submits to the normal booking
  # endpoint with asap=1.
  #
  # Pre-fill from links: ?pickup=&dropoff= (text), ?lat=&lng= (pickup
  # coordinates), ?from=&to= (place ids), ?pax=.
  class NowController < BaseController
    def show
      unless current_tenant.asap_enabled?
        return redirect_to site_path(:booking_page), alert: t("public.now.unavailable")
      end

      @request = prefilled_request
      @places = current_tenant.featured_places.to_a
    end

    private
      def prefilled_request
        request = Bookings::Request.new(
          asap: true,
          pickup_address: params[:pickup].to_s.truncate(255).presence,
          dropoff_address: params[:dropoff].to_s.truncate(255).presence,
          passengers: params[:pax].to_i.clamp(1, 8)
        )
        if params[:lat].present? && params[:lng].present?
          request.pickup_lat = params[:lat].to_f.clamp(-90, 90)
          request.pickup_lng = params[:lng].to_f.clamp(-180, 180)
          request.pickup_address ||= t("public.now.shared_location")
        end
        if (from = current_tenant.places.find_by(id: params[:from]))
          request.pickup_address = from.name
          request.pickup_place_id = from.id
        end
        if (to = current_tenant.places.find_by(id: params[:to]))
          request.dropoff_address = to.name
          request.dropoff_place_id = to.id
        end
        request
      end
  end
end
