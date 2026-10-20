module Public
  # "Taxi Bendern": one landing page per place the firm serves, with prices
  # from that place, a pre-filled Taxi-now button and the places around it.
  class LocalitiesController < BaseController
    def show
      @localities = Discovery::Localities.new(current_tenant)
      @place = @localities.find(params[:place].to_s) or raise ActiveRecord::RecordNotFound
      @local = @localities.local?(@place)
      @rows = @localities.price_rows(@place)
      @nearby = @localities.nearby(@place)
      @tariff = current_tenant.tariff_for("standard")
      @profile = Discovery::Profile.new(current_tenant)
    end
  end
end
