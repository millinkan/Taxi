# Absolute links that go out in SMS and email. A firm with its own domain gets links on
# that domain; everyone else is served under the platform host and their slug.
class TenantUrls
  def initialize(tenant)
    @tenant = tenant
  end

  def self.platform_base
    cfg = Rails.configuration.x.platform
    "#{cfg.protocol}://#{cfg.host}"
  end

  def public_base
    if @tenant.custom_domain.present?
      "https://#{@tenant.custom_domain}"
    else
      "#{self.class.platform_base}/#{@tenant.slug}"
    end
  end

  def booking_page(params = {})
    params.any? ? "#{public_base}?#{params.to_query}" : public_base
  end

  def status_page(booking) = "#{public_base}/b/#{booking.public_token}"
  def deals_page = "#{public_base}/deals"
  def privacy_page = "#{public_base}/privacy"

  # "Taxi now". Search engines and AI assistants link here, optionally with
  # ?pickup=&dropoff=&lat=&lng= so the customer lands on a filled-in form.
  def now_page(params = {})
    params.any? ? "#{public_base}/now?#{params.to_query}" : "#{public_base}/now"
  end

  def route_page(route) = "#{public_base}/routes/#{route.to_param}"
  def locality_page(place) = "#{public_base}/taxi/#{place.slug}"
  def sitemap = "#{public_base}/sitemap.xml"
  def llms_txt = "#{public_base}/llms.txt"
  def discovery_feed = "#{public_base}/discovery.json"

  # Dispatcher links always live on the platform host: one place to secure.
  def dispatch_link(booking) = "#{self.class.platform_base}/d/#{booking.dispatch_token}"
end
