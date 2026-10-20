# One inbound phone call, whoever answered it. The transcript is an array of
# { "role" => "caller" | "agent", "text" => "..." } hashes.
class CallLog < ApplicationRecord
  include TenantOwned

  OUTCOMES = %w[in_progress booked transferred voicemail callback_requested information abandoned failed].freeze
  HANDLERS = %w[ai fallback].freeze

  belongs_to :booking, optional: true
  belongs_to :customer, optional: true

  validates :call_sid, presence: true, uniqueness: true
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :handled_by, inclusion: { in: HANDLERS }

  scope :recent, -> { order(created_at: :desc) }
  scope :answered_by_ai, -> { where(handled_by: "ai") }

  def converted? = booking_id.present?
end
