require "openssl"

module Discovery
  # Tells search engines that a firm's pages are new or changed, so they are
  # crawled in minutes instead of weeks.
  #
  #   indexnow  One POST reaches Bing (which also feeds ChatGPT search and
  #             Copilot), Yandex, Seznam, Naver and others. Needs no account:
  #             ownership is proven by the key file at /indexnow-key.txt.
  #   google    Google has no instant push for ordinary pages. The supported
  #             route is submitting the sitemap through the Search Console
  #             API, which needs a service account added as an owner of the
  #             property (see docs/DISCOVERY.md). Skipped when not configured.
  class Pusher
    INDEXNOW_ENDPOINT = "https://api.indexnow.org/indexnow".freeze
    GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
    GOOGLE_SCOPE = "https://www.googleapis.com/auth/webmasters".freeze

    # Swappable in tests.
    class_attribute :http, default: HttpJson

    # Queues one push per channel and returns them, so the admin sees each
    # one's outcome on the next page load. only_changed: see AutoPush.
    def self.enqueue(tenant, user: nil, wait: 0, only_changed: false)
      DiscoveryPush::CHANNELS.map do |channel|
        push = tenant.discovery_pushes.create!(channel: channel, user: user)
        DiscoveryPushJob.set(wait: wait).perform_later(push.id, only_changed: only_changed)
        push
      end
    end

    def initialize(push, only_changed: false)
      @push = push
      @tenant = push.tenant
      @profile = Profile.new(@tenant)
      @only_changed = only_changed
    end

    def call
      urls = @only_changed ? changed_urls : @profile.urls_to_push
      @push.update!(urls_count: urls.size)
      return @push.finish!("skipped", "no pages changed since the last push") if urls.empty?

      status, detail = public_send(:"push_#{@push.channel}", urls)
      @push.finish!(status, detail)
    rescue HttpJson::Error, OpenSSL::PKey::PKeyError, JSON::ParserError, KeyError => e
      @push.finish!("failed", e.message)
    end

    # Pages modified since this channel's last successful push. A firm-level
    # change (name, phone, hours) shows on every page, so it resends them all.
    def changed_urls
      since = @tenant.discovery_pushes.where(channel: @push.channel, status: "ok")
                     .where.not(id: @push.id).maximum(:created_at)
      return @profile.urls_to_push if since.nil? || @tenant.updated_at > since

      @profile.sitemap_entries.select { |entry| entry[:lastmod] > since }.pluck(:loc)
    end

    def push_indexnow(urls)
      host = URI(urls.first).host
      return [ "skipped", "#{host} is not a public host" ] if local_host?(host)

      base = "#{URI(urls.first).scheme}://#{URI(urls.first).authority}"
      http.post_json(INDEXNOW_ENDPOINT, body: {
        host: host, key: Discovery.indexnow_key, keyLocation: "#{base}/indexnow-key.txt", urlList: urls
      })
      [ "ok", "#{urls.size} URLs accepted" ]
    end

    def push_google(_urls)
      credentials = Discovery.google_credentials
      return [ "skipped", "Search Console not configured (GOOGLE_SERVICE_ACCOUNT_JSON)" ] unless credentials

      site = google_property
      sitemap = TenantUrls.new(@tenant).sitemap
      token = google_access_token(credentials)
      http.put("https://www.googleapis.com/webmasters/v3/sites/#{ERB::Util.url_encode(site)}/sitemaps/#{ERB::Util.url_encode(sitemap)}",
               headers: { "Authorization" => "Bearer #{token}" })
      [ "ok", "sitemap submitted to #{site}" ]
    end

    private
      def local_host?(host)
        host.blank? || host == "localhost" || host.end_with?(".localhost", ".test", ".example") ||
          host.match?(/\A(127\.|10\.|192\.168\.|0\.0\.0\.0)/)
      end

      # A custom domain is its own "Domain property"; firms under the
      # platform host share the platform's URL-prefix property.
      def google_property
        return "sc-domain:#{@tenant.custom_domain}" if @tenant.custom_domain.present?

        Rails.configuration.x.discovery.google_site.presence || "#{TenantUrls.platform_base}/"
      end

      def google_access_token(credentials)
        now = Time.current.to_i
        segments = [
          { alg: "RS256", typ: "JWT" },
          { iss: credentials.fetch("client_email"), scope: GOOGLE_SCOPE, aud: GOOGLE_TOKEN_URL, iat: now, exp: now + 3600 }
        ].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }
        signature = OpenSSL::PKey::RSA.new(credentials.fetch("private_key")).sign("SHA256", segments.join("."))
        assertion = [ *segments, Base64.urlsafe_encode64(signature, padding: false) ].join(".")

        http.post_form(GOOGLE_TOKEN_URL, form: {
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion
        }).fetch("access_token")
      end
  end
end
