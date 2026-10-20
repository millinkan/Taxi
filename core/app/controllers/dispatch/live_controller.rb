module Dispatch
  # Live map of every car on an active ride, updated over a WebSocket.
  class LiveController < StaffController
    before_action :require_tenant!
    before_action :require_dispatcher!

    def show
      @trips = current_tenant.bookings.committed.includes(:customer, :vehicle)
                             .where(pickup_at: 12.hours.ago..1.day.from_now).order(:pickup_at).to_a
      @cars = @trips.filter_map { |trip| Tracking.position(trip) }
    end
  end
end
