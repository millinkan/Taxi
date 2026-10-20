# The small, fixed set of vehicle classes a customer can ask for.
module VehicleCategory
  ALL = %w[standard van premium].freeze
  DEFAULT_SEATS = { "standard" => 4, "van" => 8, "premium" => 3 }.freeze

  module_function

  def valid?(category) = ALL.include?(category.to_s)

  # Smallest category that fits the party, used when the caller does not say.
  def for_passengers(count)
    count.to_i > 4 ? "van" : "standard"
  end
end
