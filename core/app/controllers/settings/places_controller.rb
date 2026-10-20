module Settings
  class PlacesController < BaseController
    before_action :set_place, only: %i[edit update destroy]

    def index
      @places = current_tenant.places.order(:position, :name)
    end

    def new
      @place = current_tenant.places.new(radius_m: 1500)
    end

    def create
      @place = current_tenant.places.new(place_params)
      if @place.save
        redirect_to settings_places_path, notice: t("settings.flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @place.update(place_params)
        redirect_to settings_places_path, notice: t("settings.flash.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @place.destroy
      redirect_to settings_places_path, notice: t("settings.flash.deleted")
    end

    private
      def set_place
        @place = current_tenant.places.find(params[:id])
      end

      def place_params
        params.require(:place).permit(:name, :kind, :address, :lat, :lng, :radius_m, :aliases, :featured, :position)
      end
  end
end
