# One submission of a firm's public pages to a search engine (IndexNow for
# Bing, Copilot, ChatGPT search and others; Google Search Console). Kept as a
# log so the admin can see what was pushed, when, and what the engine said.
class DiscoveryPush < ApplicationRecord
  include TenantOwned

  CHANNELS = %w[indexnow google].freeze
  STATUSES = %w[pending ok failed skipped].freeze

  belongs_to :user, optional: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :automatic, -> { where(user_id: nil) }

  def automatic? = user_id.nil?

  def finish!(status, detail = nil)
    update!(status: status, detail: detail.to_s.truncate(250).presence)
  end
end
