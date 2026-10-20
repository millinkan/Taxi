module Dispatch
  # The live board: what needs a decision now, what is happening today, and
  # what is coming up. Designed for a phone held by a driver between rides.
  class BoardController < StaffController
    before_action :require_tenant!

    def show
      bookings = current_tenant.bookings.includes(:customer, :vehicle, :driver)
      today = Time.zone.today

      # "Taxi now" requests first: someone is standing outside waiting.
      @pending = bookings.pending.order(asap: :desc, pickup_at: :asc).to_a
      @today = bookings.committed.picked_up_between(today.all_day).order(:pickup_at).to_a
      @upcoming = bookings.committed.picked_up_between(today.tomorrow.beginning_of_day..14.days.from_now)
                          .order(:pickup_at).limit(50).to_a
      @done_today = bookings.where(status: %w[completed no_show]).picked_up_between(today.all_day).count
      @open_deals = current_tenant.empty_legs.bookable.count
    end
  end
end
