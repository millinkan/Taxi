module Admin
  # Platform operator console: onboard firms, edit their core settings, and
  # "act as" a firm to configure it or help its staff.
  class TenantsController < StaffController
    TENANT_FIELDS = %i[
      name slug legal_name licence_number status default_locale public_phone email
      dispatcher_name dispatcher_phone voice_number voice_agent_enabled custom_domain sms_sender_id
      google_business_url
    ].freeze

    before_action :require_platform_admin!
    before_action :set_tenant, only: %i[show edit update act_as]

    def index
      @tenants = Tenant.order(:name)
      @booking_counts = Booking.where(created_at: 30.days.ago..).group(:tenant_id).count
    end

    def show
      @owners = @tenant.users.order(:name)
    end

    def new
      @tenant = Tenant.new(status: "active")
      @owner = User.new
      @region = "liechtenstein"
    end

    def create
      @region = params[:region].presence_in(TenantOnboarding.regions)
      result = TenantOnboarding.new(
        tenant_attrs: params.require(:tenant).permit(*TENANT_FIELDS),
        owner_attrs: params.require(:owner).permit(:name, :email_address, :phone, :password),
        region: @region
      ).call

      if result.success?
        redirect_to admin_tenant_path(result.tenant), notice: t("admin.flash.onboarded", name: result.tenant.name)
      else
        @tenant = result.tenant
        @owner = User.new(params.require(:owner).permit(:name, :email_address, :phone))
        @errors = result.errors
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @tenant.update(params.require(:tenant).permit(*TENANT_FIELDS))
        redirect_to admin_tenant_path(@tenant), notice: t("settings.flash.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def act_as
      session[:acting_tenant_id] = @tenant.id
      redirect_to dispatch_root_path, notice: t("admin.flash.acting_as", name: @tenant.name)
    end

    def stop_acting
      session.delete(:acting_tenant_id)
      redirect_to admin_tenants_path
    end

    private
      def set_tenant
        @tenant = Tenant.find(params[:id])
      end
  end
end
