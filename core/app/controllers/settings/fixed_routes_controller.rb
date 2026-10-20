module Settings
  class FixedRoutesController < BaseController
    before_action :set_route, only: %i[edit update destroy]
    before_action :load_places, except: %i[index destroy]

    def index
      @routes = current_tenant.fixed_routes.includes(:origin_place, :destination_place)
                              .order(:vehicle_category, :price_cents)
    end

    def new
      @route = current_tenant.fixed_routes.new(bidirectional: true, active: true)
    end

    def create
      @route = current_tenant.fixed_routes.new(route_params)
      if @route.save
        redirect_to settings_fixed_routes_path, notice: t("settings.flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @route.update(route_params)
        redirect_to settings_fixed_routes_path, notice: t("settings.flash.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @route.destroy
      redirect_to settings_fixed_routes_path, notice: t("settings.flash.deleted")
    end

    private
      def set_route
        @route = current_tenant.fixed_routes.find(params[:id])
      end

      def load_places
        @places = current_tenant.places.order(:position, :name)
      end

      # Place ids are looked up through the tenant so a forged id from another
      # firm resolves to nil and fails validation.
      def route_params
        attrs = params.require(:fixed_route).permit(:origin_place_id, :destination_place_id, :vehicle_category,
                                                    :price, :bidirectional, :active)
        {
          origin_place: current_tenant.places.find_by(id: attrs[:origin_place_id]),
          destination_place: current_tenant.places.find_by(id: attrs[:destination_place_id]),
          vehicle_category: attrs[:vehicle_category],
          price_cents: to_cents(attrs[:price]),
          bidirectional: attrs[:bidirectional],
          active: attrs[:active]
        }
      end
  end
end
