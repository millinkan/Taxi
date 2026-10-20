# Recurring (config/recurring.yml): close empty legs whose window has passed.
class ExpireEmptyLegsJob < ApplicationJob
  queue_as :default

  def perform
    EmptyLeg.listed.where(available_until: ...Time.current)
            .update_all(status: "expired", updated_at: Time.current)
  end
end
