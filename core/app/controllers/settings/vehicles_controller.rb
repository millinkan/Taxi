module Settings
  class VehiclesController < BaseController
    before_action :set_vehicle, only: %i[edit update destroy]

    def index
      @vehicles = current_tenant.vehicles.order(:name)
    end

    def new
      @vehicle = current_tenant.vehicles.new(category: "standard", seats: 4, active: true)
    end

    def create
      @vehicle = current_tenant.vehicles.new(vehicle_params)
      if @vehicle.save
        redirect_to settings_vehicles_path, notice: t("settings.flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @vehicle.update(vehicle_params)
        redirect_to settings_vehicles_path, notice: t("settings.flash.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @vehicle.destroy
      redirect_to settings_vehicles_path, notice: t("settings.flash.deleted")
    end

    private
      def set_vehicle
        @vehicle = current_tenant.vehicles.find(params[:id])
      end

      def vehicle_params
        params.require(:vehicle).permit(:name, :plate, :category, :seats, :active)
      end
  end
end
