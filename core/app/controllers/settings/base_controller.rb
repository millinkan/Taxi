module Settings
  class BaseController < StaffController
    before_action :require_tenant!
    before_action :require_owner!

    private
      # "45.50" (francs, as typed) -> 4550 (Rappen, as stored).
      def to_cents(value)
        return nil if value.blank?

        (BigDecimal(value.to_s.tr(",", ".").delete("'")) * 100).round
      rescue ArgumentError
        nil
      end
  end
end
