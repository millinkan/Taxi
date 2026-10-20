class MessageLog < ApplicationRecord
  include TenantOwned

  CHANNELS = %w[sms whatsapp email].freeze
  STATUSES = %w[queued sent failed skipped].freeze

  belongs_to :booking, optional: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :purpose, :to, :body, presence: true
  validates :subject, presence: true, if: :email?

  scope :recent, -> { order(created_at: :desc) }

  def email? = channel == "email"
end
