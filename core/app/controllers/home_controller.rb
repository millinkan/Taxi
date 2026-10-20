# "/" on the platform host: send each kind of user to where they work.
class HomeController < StaffController
  def show
    if current_user.platform_admin? && !current_tenant
      redirect_to admin_tenants_path
    elsif current_user.can_dispatch? || current_user.role == "driver"
      redirect_to dispatch_root_path
    else
      redirect_to dashboard_path
    end
  end
end
