# Who caused a change. Stored on every BookingEvent so the timeline answers
# "who confirmed this?" without guesswork.
class Actor < Data.define(:type, :id)
  TYPES = %w[system user customer voice_agent dispatch_link].freeze

  def self.system = new(type: "system", id: nil)
  def self.user(user) = new(type: "user", id: user.id)
  def self.customer(customer) = new(type: "customer", id: customer&.id)
  def self.voice_agent = new(type: "voice_agent", id: nil)
  def self.dispatch_link = new(type: "dispatch_link", id: nil)
end
