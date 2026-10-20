# Every live car of one firm, for the dispatcher's live map. Staff only.
class FleetChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    user = current_user
    allowed = tenant && user&.active? && user.can_dispatch? &&
              (user.platform_admin? || user.tenant_id == tenant.id)
    return reject unless allowed

    stream_from Tracking.fleet_stream(tenant)
  end
end
