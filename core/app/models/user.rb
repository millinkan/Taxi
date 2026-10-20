class User < ApplicationRecord
  ROLES = %w[platform_admin owner dispatcher driver].freeze

  belongs_to :tenant, optional: true
  has_many :sessions, dependent: :destroy

  has_secure_password

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :phone, with: ->(p) { PhoneNumber.normalize(p) || p.to_s.strip.presence }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: ROLES }
  validates :locale, inclusion: { in: Tenant::LOCALES }
  validates :password, length: { minimum: 10 }, allow_nil: true
  validates :tenant, presence: true, unless: :platform_admin?
  validates :tenant, absence: true, if: :platform_admin?

  scope :active, -> { where(active: true) }
  scope :drivers, -> { where(role: %w[owner dispatcher driver]) }

  def platform_admin? = role == "platform_admin"
  def owner? = role == "owner"

  # Owners see revenue and settings; dispatchers run the board.
  def can_manage_settings? = owner? || platform_admin?
  def can_dispatch? = role.in?(%w[owner dispatcher platform_admin])
end
