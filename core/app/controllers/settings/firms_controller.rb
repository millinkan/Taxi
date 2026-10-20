module Settings
  class FirmsController < BaseController
    FIELDS = %i[
      name legal_name licence_number default_locale brand_color logo_url public_phone email website_url
      google_review_url dispatcher_name dispatcher_phone sms_sender_id voice_agent_enabled voice_greeting
      service_center_lat service_center_lng service_radius_km home_area_label min_lead_minutes max_advance_days
      auto_confirm auto_confirm_min_lead_hours dispatch_escalation_minutes free_cancellation_hours
      empty_legs_enabled empty_leg_discount_percent empty_leg_min_distance_km review_requests_enabled
      missed_call_textback_enabled data_retention_days asap_enabled asap_response_minutes opening_hours
      google_business_url
    ].freeze

    def edit
      @tenant = current_tenant
    end

    def update
      @tenant = current_tenant
      if @tenant.update(params.require(:tenant).permit(*FIELDS))
        redirect_to edit_settings_firm_path, notice: t("settings.flash.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
