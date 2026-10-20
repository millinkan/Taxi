module Dispatch
  class CallsController < StaffController
    before_action :require_tenant!
    before_action :require_dispatcher!

    def index
      @calls = current_tenant.call_logs.recent.includes(:booking, :customer).limit(100)
    end

    def show
      @call = current_tenant.call_logs.find(params[:id])
    end
  end
end
