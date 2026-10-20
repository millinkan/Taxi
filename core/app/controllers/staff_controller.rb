# Base for everything behind the login: dispatch board, dashboard, settings.
# Sets Current.tenant from the signed-in user. Platform admins can act as a
# firm (for onboarding and support); that choice is kept in the session.
class StaffController < ApplicationController
  include PriceFormatting

  layout "staff"

  before_action :require_active_user
  before_action :set_current_tenant
  before_action :set_locale
  around_action :use_tenant_time_zone

  helper_method :current_tenant, :current_user, :acting_as_tenant?

  private
    def current_tenant = Current.tenant
    def current_user = Current.user

    def acting_as_tenant?
      current_user&.platform_admin? && current_tenant.present?
    end

    def require_active_user
      return if current_user&.active?

      terminate_session if Current.session
      redirect_to new_session_path, alert: t("staff.account_inactive")
    end

    def set_current_tenant
      Current.tenant =
        if current_user.platform_admin?
          Tenant.find_by(id: session[:acting_tenant_id])
        else
          current_user.tenant
        end
    end

    # Pages that only make sense inside a firm.
    def require_tenant!
      return if current_tenant

      redirect_to(current_user.platform_admin? ? admin_tenants_path : root_path,
                  alert: t("staff.choose_tenant"))
    end

    def require_dispatcher!
      head :forbidden unless current_user.can_dispatch?
    end

    def require_owner!
      head :forbidden unless current_user.can_manage_settings?
    end

    def require_platform_admin!
      head :forbidden unless current_user.platform_admin?
    end

    def set_locale
      I18n.locale = current_user&.locale.presence_in(Tenant::LOCALES) || I18n.default_locale
    end

    def use_tenant_time_zone(&)
      Time.use_zone(current_tenant&.time_zone || "Europe/Vaduz", &)
    end

    def actor = Actor.user(current_user)
end
