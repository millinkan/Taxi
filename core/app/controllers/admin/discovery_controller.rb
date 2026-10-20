require "csv"

module Admin
  # Getting a firm found: readiness checklist, the links for its Google
  # Business Profile, the feeds AI assistants read, a "push now" button that
  # notifies search engines, and what discovery has brought in so far.
  class DiscoveryController < StaffController
    # Hosts whose referrals count as "came from an AI assistant".
    AI_REFERRERS = %w[chatgpt.com openai.com perplexity.ai gemini.google.com copilot.microsoft.com claude.ai].freeze

    before_action :require_platform_admin!
    before_action :set_tenant

    def show
      @keywords = Discovery::Keywords.new(@tenant)
      respond_to do |format|
        format.html do
          @profile = Discovery::Profile.new(@tenant)
          @pushes = @tenant.discovery_pushes.recent.includes(:user).limit(20).to_a
          @stats = stats
          @regions = TenantOnboarding.regions
        end
        format.csv do
          send_data keywords_csv, filename: "#{@tenant.slug}-search-keywords.csv", type: "text/csv"
        end
      end
    end

    def create
      pushes = Discovery::Pusher.enqueue(@tenant, user: current_user)
      redirect_to admin_tenant_discovery_path(@tenant), notice: t("admin.discovery.flash.pushed", count: pushes.size)
    end

    # Adds the region's localities the firm is missing, so each gets a page.
    def sync_places
      region = params[:region].presence_in(TenantOnboarding.regions)
      return head :unprocessable_entity unless region

      added = TenantOnboarding.sync_places(@tenant, region)
      redirect_to admin_tenant_discovery_path(@tenant),
                  notice: t("admin.discovery.flash.places_added", count: added.size, names: added.map(&:name).to_sentence)
    end

    private
      def set_tenant
        @tenant = Tenant.find(params[:tenant_id])
      end

      # Google Ads Editor import: one row per keyword, landing on the page
      # that answers it, tagged so paid bookings are attributed.
      def keywords_csv
        CSV.generate do |csv|
          csv << [ "Ad group", "Keyword", "Criterion Type", "Final URL" ]
          @keywords.all.each do |keyword|
            separator = keyword.url.include?("?") ? "&" : "?"
            url = "#{keyword.url}#{separator}#{{ utm_source: "google", utm_medium: "cpc", utm_campaign: keyword.group.parameterize(locale: :de) }.to_query}"
            csv << [ keyword.group, keyword.phrase, "Phrase", url ]
          end
        end
      end

      def stats
        recent = @tenant.bookings.where(created_at: 30.days.ago..)
        from_ai = recent.where(utm_source: Discovery::Profile::AI_UTM[:utm_source])
                        .or(recent.where(AI_REFERRERS.map { "bookings.referrer LIKE ?" }.join(" OR "),
                                         *AI_REFERRERS.map { |host| "%#{host}%" }))
        asap = recent.where(asap: true)
        {
          google_profile: recent.where(utm_source: "google", utm_medium: "business_profile").count,
          ai: from_ai.count,
          asap: asap.count,
          asap_confirmed: asap.where.not(eta_minutes: nil).count
        }
      end
  end
end
