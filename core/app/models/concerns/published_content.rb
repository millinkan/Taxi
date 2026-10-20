# A model whose changes appear on a firm's public pages. Every committed
# change schedules an automatic push to search engines (Discovery::AutoPush).
module PublishedContent
  extend ActiveSupport::Concern

  included do
    after_commit :schedule_discovery_push, if: :published_change?
  end

  private
    def schedule_discovery_push = Discovery::AutoPush.schedule(publishing_tenant)
    def publishing_tenant = tenant
    def published_change? = true
end
