class DashboardController < StaffController
  before_action :require_tenant!
  before_action :require_owner!

  def show
    @report = PerformanceReport.new(current_tenant, params[:period])
  end
end
