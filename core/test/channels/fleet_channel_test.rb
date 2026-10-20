require "test_helper"

class FleetChannelTest < ActionCable::Channel::TestCase
  setup do
    @tenant = create_tenant(slug: "taxi-fleet")
  end

  test "the firm's dispatchers see the fleet" do
    stub_connection current_user: owner_of(@tenant)
    subscribe tenant_id: @tenant.id
    assert subscription.confirmed?
    assert_has_stream "fleet:#{@tenant.id}"
  end

  test "platform admins may watch any firm" do
    stub_connection current_user: create_platform_admin
    subscribe tenant_id: @tenant.id
    assert subscription.confirmed?
  end

  test "other firms, drivers and anonymous visitors are rejected" do
    other = create_tenant(slug: "taxi-rival")
    stub_connection current_user: owner_of(other)
    subscribe tenant_id: @tenant.id
    assert subscription.rejected?

    stub_connection current_user: create_user(tenant: @tenant, role: "driver")
    subscribe tenant_id: @tenant.id
    assert subscription.rejected?

    stub_connection current_user: nil
    subscribe tenant_id: @tenant.id
    assert subscription.rejected?
  end
end
