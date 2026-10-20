module Bookings
  # Status changes plus their side effects (SMS, empty legs, follow-up jobs).
  # Controllers and the internal API call these methods; they never call
  # Booking#transition! directly.
  class Lifecycle
    REVIEW_DELAY = 1.hour
    # Arrival times the dispatcher can promise for a "taxi now" request.
    ETA_CHOICES = [ 5, 10, 15, 20, 30 ].freeze
    DEFAULT_ETA = 15

    def initialize(booking)
      @booking = booking
      @tenant = booking.tenant
      @notifier = Notifier.new(booking)
    end

    # Right after creation: confirm automatically when it is safe, otherwise
    # alert the dispatcher and start the escalation timer.
    #
    # A "taxi now" request is never auto-confirmed (nobody knows where the cars
    # are) and never left hanging: if no one answers with an ETA in time, the
    # customer is told straight away so they can look elsewhere.
    def after_create(actor: Actor.system)
      if @booking.asap?
        @notifier.dispatcher_new_booking
        @notifier.customer_received
        ExpireAsapRequestJob.set(wait: @tenant.asap_response_minutes.minutes).perform_later(@booking.id)
      elsif auto_confirmable?
        confirm!(actor: Actor.system, auto: true)
        @notifier.dispatcher_new_booking
      else
        @notifier.dispatcher_new_booking
        @notifier.customer_received
        EscalatePendingBookingJob.set(wait: @tenant.dispatch_escalation_minutes.minutes)
                                 .perform_later(@booking.id)
      end
    end

    def confirm!(actor:, auto: false, eta_minutes: nil)
      if @booking.asap?
        eta = (eta_minutes.presence || DEFAULT_ETA).to_i.clamp(1, 90)
        @booking.update!(eta_minutes: eta, pickup_at: eta.minutes.from_now)
      end
      @booking.transition!(:confirmed, actor: actor, reason: auto ? "auto_confirmed" : nil)
      @notifier.customer_confirmed
      EmptyLegs::Publisher.new(@booking).publish
      @booking
    end

    def decline!(actor:, reason: nil)
      @booking.transition!(:declined, actor: actor, reason: reason)
      @notifier.customer_declined
      release_empty_leg
      @booking
    end

    # Nobody took the "taxi now" request in time.
    def expire_asap!
      return @booking unless @booking.asap? && @booking.pending?

      @booking.transition!(:declined, actor: Actor.system, reason: "no_response")
      @notifier.customer_asap_unavailable
      @notifier.dispatcher_asap_missed
      @booking
    end

    def start!(actor:)
      @booking.transition!(:on_the_way, actor: actor)
      @notifier.customer_on_the_way
      @booking
    end

    def complete!(actor:, final_price_cents: nil)
      @booking.transition!(:completed, actor: actor, final_price_cents: final_price_cents)
      Tracking.stop(@booking)
      RequestReviewJob.set(wait: REVIEW_DELAY).perform_later(@booking.id)
      @booking
    end

    def no_show!(actor:)
      @booking.transition!(:no_show, actor: actor)
      Tracking.stop(@booking)
      @booking
    end

    def cancel!(actor:, reason: nil)
      @booking.transition!(:cancelled, actor: actor, reason: reason)
      Tracking.stop(@booking)
      if actor.type == "customer"
        @notifier.dispatcher_cancelled_by_customer
        @notifier.customer_cancellation_receipt
      else
        @notifier.customer_cancelled
      end
      @booking.empty_legs_created.listed.update_all(status: "withdrawn", updated_at: Time.current)
      release_empty_leg
      @booking
    end

    # A cancelled empty-leg booking puts the seat back on sale while it can
    # still be used.
    def release_empty_leg
      return unless @booking.empty_leg_id

      # Decided in the database, not on a possibly stale in-memory copy.
      EmptyLeg.where(id: @booking.empty_leg_id, status: "booked", available_until: Time.current..)
              .update_all(status: "open", updated_at: Time.current)
    end

    def auto_confirmable?
      @tenant.auto_confirm? &&
        @booking.pending? &&
        @booking.price_known? &&
        !@booking.price_estimated? &&
        @booking.pickup_at >= @tenant.auto_confirm_min_lead_hours.hours.from_now &&
        DispatchCapacity.new(@tenant).available?(
          pickup_at: @booking.pickup_at, duration_s: @booking.duration_s,
          passengers: @booking.passengers, exclude_id: @booking.id,
          leaves_area: !@tenant.within_service_area?(@booking.dropoff_point)
        )
    end
  end
end
