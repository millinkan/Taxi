module Discovery
  # Keeps search engines and AI assistants current without anyone pressing a
  # button: a push goes out a few minutes after anything public changes
  # (prices, places, contact details, deals), and once a day for every active
  # firm (DiscoveryRefreshJob).
  #
  # Automatic IndexNow pushes carry only the URLs changed since the last
  # successful one; the protocol asks for changed URLs, and engines throttle
  # keys that resubmit unchanged ones.
  module AutoPush
    # Collects a burst of edits (onboarding, a price list update) into one push.
    DELAY = 5.minutes
    # A pending push older than this is treated as lost and no longer blocks.
    STALE_AFTER = 1.hour

    module_function

    def enabled? = Rails.configuration.x.discovery.auto_push

    def schedule(tenant, wait: DELAY)
      return [] unless enabled? && tenant&.active? && !tenant.destroyed?
      return [] if tenant.discovery_pushes.automatic.where(status: "pending", created_at: STALE_AFTER.ago..).exists?
      return [] unless Profile.new(tenant).ready?

      Pusher.enqueue(tenant, wait: wait, only_changed: true)
    end
  end
end
