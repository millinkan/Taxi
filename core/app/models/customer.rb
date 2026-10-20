class Customer < ApplicationRecord
  include TenantOwned

  has_many :bookings, dependent: :restrict_with_error
  has_many :call_logs, dependent: :nullify

  normalizes :phone, with: ->(p) { PhoneNumber.normalize(p) || p.to_s.strip }
  normalizes :email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :phone, presence: true, uniqueness: { scope: :tenant_id },
                    format: { with: PhoneNumber::E164 }
  validates :locale, inclusion: { in: Tenant::LOCALES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true

  def repeat? = bookings_count > 1

  def display_name
    name.presence || PhoneNumber.display(phone)
  end

  # GDPR: keep the booking history for accounting, drop everything personal.
  def anonymize!
    update_columns(name: nil, email: nil, notes: nil,
                   phone: "+0#{id.to_s.rjust(9, "0")}", anonymized_at: Time.current)
  end
end
