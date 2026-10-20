require "test_helper"

# Search engines hear about a firm's changes without anyone pressing a button.
class DiscoveryAutoPushTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :calls

    def initialize = @calls = []
    def post_json(url, body:, headers: {}) = (@calls << { url: url, body: body }) && {}
  end

  setup do
    @tenant = create_tenant(slug: "taxi-auto", custom_domain: "taxi-auto.li")
    @route = Discovery::Profile.new(@tenant).route_pages.first
    @http = FakeHttp.new
    Discovery::Pusher.http = @http
    Rails.configuration.x.discovery.auto_push = true
  end

  teardown do
    Rails.configuration.x.discovery.auto_push = false
    Discovery::Pusher.http = HttpJson
  end

  test "a price change schedules one delayed push per channel" do
    assert_enqueued_with(job: DiscoveryPushJob, at: Discovery::AutoPush::DELAY.from_now) do
      @route.update!(price_cents: @route.price_cents + 1000)
    end
    assert_equal %w[google indexnow], @tenant.discovery_pushes.automatic.pluck(:channel).sort
  end

  test "a burst of edits is collected into the push already waiting" do
    @route.update!(price_cents: @route.price_cents + 1000)
    assert_no_enqueued_jobs(only: DiscoveryPushJob) do
      place(@tenant, "Vaduz").update!(aliases: "Vaduz Zentrum")
      @tenant.update!(opening_hours: "Mo-Su 05:00-02:00")
    end
  end

  test "internal settings and paused firms trigger nothing" do
    assert_no_enqueued_jobs(only: DiscoveryPushJob) { @tenant.update!(auto_confirm: true) }

    @tenant.update!(status: "paused")
    assert_no_enqueued_jobs(only: DiscoveryPushJob) { @route.update!(price_cents: 99_000) }
  end

  test "automatic IndexNow pushes send only the pages that changed" do
    first = @tenant.discovery_pushes.create!(channel: "indexnow")
    Discovery::Pusher.new(first, only_changed: true).call
    all_urls = @http.calls.sole[:body][:urlList]

    travel 1.hour
    @route.update!(price_cents: @route.price_cents + 1000)
    second = @tenant.discovery_pushes.create!(channel: "indexnow")
    Discovery::Pusher.new(second, only_changed: true).call

    changed = @http.calls.last[:body][:urlList]
    assert_operator changed.size, :<, all_urls.size
    urls = TenantUrls.new(@tenant)
    assert_includes changed, urls.route_page(@route)
    assert_includes changed, urls.locality_page(@route.destination_place)

    travel 1.hour
    third = @tenant.discovery_pushes.create!(channel: "indexnow")
    Discovery::Pusher.new(third, only_changed: true).call
    assert_equal 2, @http.calls.size
    assert_equal "skipped", third.reload.status
  end

  test "the daily refresh pushes every active firm" do
    paused = create_tenant(slug: "taxi-paused", status: "paused")
    @tenant.discovery_pushes.delete_all

    assert_enqueued_jobs 2, only: DiscoveryPushJob do
      DiscoveryRefreshJob.perform_now
    end
    assert_empty paused.discovery_pushes
  end
end
