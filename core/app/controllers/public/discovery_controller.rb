module Public
  # Machine-readable descriptions of one firm for search engines and AI
  # assistants. All three come from Discovery::Profile.
  class DiscoveryController < BaseController
    skip_before_action :capture_attribution

    before_action { expires_in 1.hour, public: true }

    def sitemap
      @entries = profile.sitemap_entries
      render formats: :xml, content_type: "application/xml"
    end

    def llms
      render plain: profile.llms_txt, content_type: "text/plain"
    end

    def feed
      render json: profile.feed
    end

    private
      def profile = Discovery::Profile.new(current_tenant)
  end
end
