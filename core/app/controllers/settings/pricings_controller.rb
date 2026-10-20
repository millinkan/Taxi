module Settings
  # One form for the metered tariff of every vehicle category.
  class PricingsController < BaseController
    MONEY_FIELDS = %w[base_fare per_km per_minute minimum_fare rounding].freeze

    def edit
      @tariffs = tariffs
    end

    def update
      @tariffs = tariffs
      submitted = params.fetch(:tariffs, {})

      saved = Tariff.transaction do
        @tariffs.each do |tariff|
          attrs = submitted.fetch(tariff.vehicle_category, {}).permit(*MONEY_FIELDS, :night_surcharge_percent,
                                                                       :night_starts_at, :night_ends_at)
          MONEY_FIELDS.each do |field|
            cents = to_cents(attrs[field])
            tariff.public_send(:"#{field}_cents=", cents) unless cents.nil?
          end
          tariff.assign_attributes(attrs.slice(:night_surcharge_percent, :night_starts_at, :night_ends_at))
        end
        @tariffs.all?(&:save) || raise(ActiveRecord::Rollback)
      end

      if saved
        redirect_to edit_settings_pricing_path, notice: t("settings.flash.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def tariffs
        VehicleCategory::ALL.map do |category|
          current_tenant.tariffs.find_or_initialize_by(vehicle_category: category)
        end
      end
  end
end
