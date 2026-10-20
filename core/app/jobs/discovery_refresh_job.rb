# Daily sweep so every active firm is resubmitted even when nothing triggered
# an automatic push (for example a deal that expired by itself overnight).
class DiscoveryRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.active.find_each { |tenant| Discovery::AutoPush.schedule(tenant, wait: 0) }
  end
end
