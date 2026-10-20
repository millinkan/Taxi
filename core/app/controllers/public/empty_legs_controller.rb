module Public
  class EmptyLegsController < BaseController
    def index
      @deals = current_tenant.empty_legs.bookable.to_a
    end
  end
end
