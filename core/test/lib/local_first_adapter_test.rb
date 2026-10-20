require "test_helper"
require "action_cable/subscription_adapter/local_first"

class LocalFirstAdapterTest < ActiveSupport::TestCase
  # Stands in for Solid Cable: one shared bus every process reads from.
  class FakeBus
    attr_reader :published

    def initialize
      @subscribers = Hash.new { |hash, key| hash[key] = [] }
      @published = []
    end

    def broadcast(channel, payload)
      @published << payload
      @subscribers[channel].each { |callback| callback.call(payload) }
    end

    def subscribe(channel, callback, success_callback = nil)
      @subscribers[channel] << callback
      success_callback&.call
    end

    def unsubscribe(channel, callback) = @subscribers[channel].delete(callback)
    def shutdown; end
  end

  setup do
    @bus = FakeBus.new
    server = ActionCable.server
    # Two web processes sharing the bus; Inline = synchronous local delivery.
    @web_a = ActionCable::SubscriptionAdapter::LocalFirst.new(
      server, local: ActionCable::SubscriptionAdapter::Inline.new(server), remote: @bus)
    @web_b = ActionCable::SubscriptionAdapter::LocalFirst.new(
      server, local: ActionCable::SubscriptionAdapter::Inline.new(server), remote: @bus)
  end

  test "subscribers in the same process get the message at once and exactly once" do
    received = []
    confirmed = false
    @web_a.subscribe("trip:1", ->(message) { received << message }, -> { confirmed = true })

    @web_a.broadcast("trip:1", '{"lat":47.15}')

    assert confirmed
    assert_equal [ '{"lat":47.15}' ], received
    assert_match(/\A\d+\.\h{8}\|\{"lat":47.15\}\z/, @bus.published.sole, "still written for other processes")
  end

  test "other processes get it through Solid Cable, untagged and once" do
    in_a = []
    in_b = []
    @web_a.subscribe("trip:1", ->(message) { in_a << message })
    @web_b.subscribe("trip:1", ->(message) { in_b << message })

    @web_a.broadcast("trip:1", '{"lat":1}')
    @web_b.broadcast("trip:1", '{"lat":2}')

    assert_equal [ '{"lat":1}', '{"lat":2}' ], in_a
    assert_equal [ '{"lat":1}', '{"lat":2}' ], in_b
  end

  test "unsubscribing stops both paths" do
    received = []
    callback = ->(message) { received << message }
    @web_a.subscribe("trip:1", callback)
    @web_a.unsubscribe("trip:1", callback)

    @web_a.broadcast("trip:1", "{}")
    @web_b.broadcast("trip:1", "{}")
    assert_empty received
  end
end
