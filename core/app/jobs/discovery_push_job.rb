# Runs one search-engine submission, queued from the admin's Discovery page
# or automatically by Discovery::AutoPush.
class DiscoveryPushJob < ApplicationJob
  queue_as :default

  def perform(push_id, only_changed: false)
    push = DiscoveryPush.find_by(id: push_id)
    return unless push&.status == "pending"

    Discovery::Pusher.new(push, only_changed: only_changed).call
  end
end
