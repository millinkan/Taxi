# Marks a model as belonging to one taxi firm.
#
# Isolation rule for the whole codebase: controllers never call Model.find on
# a tenant-owned model. They always go through the association on the current
# tenant (Current.tenant.bookings.find(id)), so a record from another firm is
# simply not found. See docs/adr/0002-multi-tenancy.md.
module TenantOwned
  extend ActiveSupport::Concern

  included do
    belongs_to :tenant
  end
end
