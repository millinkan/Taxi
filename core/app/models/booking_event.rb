class BookingEvent < ApplicationRecord
  include TenantOwned

  belongs_to :booking

  validates :action, presence: true
  validates :actor_type, inclusion: { in: Actor::TYPES }

  def actor_user
    User.find_by(id: actor_id) if actor_type == "user"
  end
end
