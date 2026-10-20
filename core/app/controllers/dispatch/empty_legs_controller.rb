module Dispatch
  class EmptyLegsController < StaffController
    before_action :require_tenant!
    before_action :require_dispatcher!

    def index
      @open = current_tenant.empty_legs.bookable.includes(:source_booking)
      @recent = current_tenant.empty_legs.where.not(status: "open").order(available_from: :desc)
                              .includes(:booking).limit(30)
    end

    # Withdraw a deal, e.g. because the car is needed elsewhere.
    def destroy
      leg = current_tenant.empty_legs.find(params[:id])
      leg.update!(status: "withdrawn") if leg.status == "open"
      redirect_to dispatch_empty_legs_path, notice: t("dispatch.flash.deal_withdrawn")
    end
  end
end
