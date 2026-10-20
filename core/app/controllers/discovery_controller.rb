# Host-level files for crawlers. On a firm's own domain they describe that
# firm; on the platform host they cover every firm served under a slug.
class DiscoveryController < ApplicationController
  allow_unauthenticated_access

  # Pages that must never appear in search results: booking status and
  # dispatcher links carry secret tokens, the rest is behind a login.
  PRIVATE_PATHS = %w[
    /b/ /*/b/ /d/ /dispatch /dashboard /settings /admin /session /passwords /exports /internal /twilio
  ].freeze

  # Search and AI-assistant crawlers, named so that a firm's pages are
  # explicitly open to them. They share the "*" group's rules (RFC 9309).
  WELCOME_CRAWLERS = %w[
    Googlebot Google-Extended Bingbot OAI-SearchBot ChatGPT-User GPTBot PerplexityBot Perplexity-User
    Claude-SearchBot Claude-User ClaudeBot Applebot Applebot-Extended DuckDuckBot
  ].freeze

  def robots
    lines = [ "User-agent: *", *WELCOME_CRAWLERS.map { |agent| "User-agent: #{agent}" },
              *PRIVATE_PATHS.map { |path| "Disallow: #{path}" }, "Allow: /", "" ]
    lines += sitemap_tenants.map { |tenant| "Sitemap: #{TenantUrls.new(tenant).sitemap}" }
    expires_in 1.hour, public: true
    render plain: lines.join("\n") + "\n", content_type: "text/plain"
  end

  # IndexNow ownership proof; see Discovery::Pusher.
  def indexnow_key
    render plain: Discovery.indexnow_key, content_type: "text/plain"
  end

  private
    def sitemap_tenants
      if (tenant = Tenant.for_host(request.host))
        [ tenant ]
      else
        Tenant.active.where(custom_domain: nil).order(:id)
      end
    end
end
