# The page a dispatcher opens from the "new booking" SMS: one screen, big
# buttons, no login. The 24-character random token in the URL is the
# credential; it only grants actions on that single booking.
class DispatchLinksController < ApplicationController
  include PriceFormatting

  allow_unauthenticated_access
  layout "public"

  before_action :set_booking
  around_action :use_tenant_time_zone
  helper_method :current_tenant

  rate_limit to: 30, within: 1.minute

  def show
  end

  def confirm = run { |lifecycle| lifecycle.confirm!(actor: Actor.dispatch_link, eta_minutes: params[:eta]) }
  def decline = run { |lifecycle| lifecycle.decline!(actor: Actor.dispatch_link, reason: params[:reason]) }
  def start = run { |lifecycle| lifecycle.start!(actor: Actor.dispatch_link) }

  def complete
    final = params[:final_price].presence && (BigDecimal(params[:final_price]) * 100).round
    run { |lifecycle| lifecycle.complete!(actor: Actor.dispatch_link, final_price_cents: final) }
  rescue ArgumentError
    redirect_to dispatch_link_path(token: @booking.dispatch_token), alert: t("dispatch.flash.invalid_price")
  end

  private
    def current_tenant = Current.tenant

    def set_booking
      @booking = Booking.includes(:tenant, :customer).find_by!(dispatch_token: params[:token].to_s)
      Current.tenant = @booking.tenant
      I18n.locale = @booking.tenant.default_locale
    end

    def use_tenant_time_zone(&)
      Time.use_zone(@booking.tenant.time_zone, &)
    end

    def run
      yield Bookings::Lifecycle.new(@booking)
      redirect_to dispatch_link_path(token: @booking.dispatch_token), notice: t("dispatch.flash.status.#{@booking.status}")
    rescue Booking::InvalidTransition
      redirect_to dispatch_link_path(token: @booking.dispatch_token), alert: t("dispatch.flash.invalid_transition")
    end
end
