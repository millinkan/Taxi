module Dispatch
  class BookingsController < StaffController
    MANUAL_FIELDS = %i[
      pickup_address pickup_place_id dropoff_address dropoff_place_id pickup_date pickup_time
      passengers luggage vehicle_category flight_number notes name phone email payment_method price_override
    ].freeze

    before_action :require_tenant!
    before_action :require_dispatcher!, except: %i[show start complete no_show]
    before_action :set_booking, except: %i[new create]

    def show
      @events = @booking.events.to_a
      @messages = @booking.message_logs.recent.to_a
      @calls = @booking.call_logs.to_a
      @vehicles = current_tenant.vehicles.active.order(:name)
      @drivers = current_tenant.users.active.drivers.order(:name)
    end

    # Phone booking taken by the dispatcher.
    def new
      @request = Bookings::Request.new(pickup_date: Time.zone.today.iso8601,
                                       pickup_time: (Time.zone.now + 30.minutes).strftime("%H:%M"),
                                       locale: current_tenant.default_locale)
      @places = current_tenant.places.order(:position, :name)
    end

    def create
      @request = Bookings::Request.new(params.require(:booking).permit(*MANUAL_FIELDS).merge(source: "phone_manual"))
      result = Bookings::Creator.new(current_tenant, actor: actor).call(@request)

      if result.success?
        booking = result.booking
        Bookings::Lifecycle.new(booking).confirm!(actor: actor) if booking.pending? && params[:confirm_now] == "1"
        redirect_to dispatch_booking_path(booking), notice: t("dispatch.flash.created", ref: booking.reference)
      else
        @errors = result.errors
        @places = current_tenant.places.order(:position, :name)
        render :new, status: :unprocessable_entity
      end
    end

    # Assignment, notes and (before confirmation) the price.
    def update
      attrs = params.require(:booking).permit(:vehicle_id, :driver_id, :internal_notes, :price)
      changes = {}
      changes[:vehicle] = current_tenant.vehicles.find_by(id: attrs[:vehicle_id]) if attrs.key?(:vehicle_id)
      changes[:driver] = current_tenant.users.find_by(id: attrs[:driver_id]) if attrs.key?(:driver_id)
      changes[:internal_notes] = attrs[:internal_notes] if attrs.key?(:internal_notes)
      if attrs[:price].present? && @booking.pending?
        changes.merge!(quoted_price_cents: (BigDecimal(attrs[:price]) * 100).round,
                       price_source: "manual", price_estimated: false)
      end

      @booking.update!(changes)
      @booking.log!("updated", actor: actor, metadata: { fields: changes.keys.map(&:to_s) })
      redirect_to dispatch_booking_path(@booking), notice: t("dispatch.flash.saved")
    rescue ArgumentError
      redirect_to dispatch_booking_path(@booking), alert: t("dispatch.flash.invalid_price")
    end

    def confirm = run { |lifecycle| lifecycle.confirm!(actor: actor, eta_minutes: params[:eta]) }
    def decline = run { |lifecycle| lifecycle.decline!(actor: actor, reason: params[:reason]) }
    def start = run { |lifecycle| lifecycle.start!(actor: actor) }
    def no_show = run { |lifecycle| lifecycle.no_show!(actor: actor) }
    def cancel = run { |lifecycle| lifecycle.cancel!(actor: actor, reason: params[:reason]) }

    def complete
      final = params[:final_price].presence && (BigDecimal(params[:final_price]) * 100).round
      run { |lifecycle| lifecycle.complete!(actor: actor, final_price_cents: final) }
    rescue ArgumentError
      redirect_to dispatch_booking_path(@booking), alert: t("dispatch.flash.invalid_price")
    end

    private
      def set_booking
        @booking = current_tenant.bookings.find(params[:id])
      end

      def run
        yield Bookings::Lifecycle.new(@booking)
        redirect_back_or_to dispatch_booking_path(@booking), notice: t("dispatch.flash.status.#{@booking.status}")
      rescue Booking::InvalidTransition
        redirect_back_or_to dispatch_booking_path(@booking), alert: t("dispatch.flash.invalid_transition")
      end
  end
end
