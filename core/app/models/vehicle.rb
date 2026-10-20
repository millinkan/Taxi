class Vehicle < ApplicationRecord
  include TenantOwned

  has_many :bookings, dependent: :nullify

  validates :name, presence: true
  validates :category, inclusion: { in: VehicleCategory::ALL }
  validates :seats, numericality: { only_integer: true, in: 1..16 }

  scope :active, -> { where(active: true) }

  def label = [ name, plate ].compact_blank.join(" · ")
end
