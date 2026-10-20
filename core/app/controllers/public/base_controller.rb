module Public
  # Customer-facing pages for one firm. The firm is resolved from the custom
  # domain or the /:tenant_slug prefix; nothing here requires a login.
  class BaseController < ApplicationController
    ATTRIBUTION_PARAMS = %w[utm_source utm_medium utm_campaign gclid].freeze

    allow_unauthenticated_access
    layout "public"

    before_action :resolve_tenant
    before_action :set_locale
    before_action :capture_attribution
    around_action :use_tenant_time_zone

    helper_method :current_tenant, :site_path, :site_url, :via_custom_domain?

    private
      def current_tenant = Current.tenant

      def via_custom_domain?
        params[:tenant_slug].blank?
      end

      def resolve_tenant
        Current.tenant =
          if via_custom_domain?
            Tenant.for_host(request.host)
          else
            Tenant.active.find_by(slug: params[:tenant_slug])
          end
        raise ActiveRecord::RecordNotFound unless Current.tenant
      end

      # Route helper that works for both mounting styles:
      #   site_path(:booking_status, token: "...")
      def site_path(name, **args)
        if via_custom_domain?
          public_send(:"domain_#{name}_path", **args)
        else
          public_send(:"firm_#{name}_path", tenant_slug: current_tenant.slug, **args)
        end
      end

      def site_url(name, **args)
        request.base_url + site_path(name, **args)
      end

      def set_locale
        requested = params[:lang].presence_in(Tenant::LOCALES)
        cookies[:lang] = { value: requested, expires: 1.year } if requested
        I18n.locale = requested || cookies[:lang].presence_in(Tenant::LOCALES) ||
                      browser_locale || current_tenant.default_locale
      end

      def browser_locale
        request.headers["Accept-Language"].to_s.scan(/[a-z]{2}/i).map(&:downcase)
               .find { |code| Tenant::LOCALES.include?(code) }
      end

      # First-touch attribution: remember where the visitor came from so the
      # eventual booking can be credited to the right ad or campaign.
      def capture_attribution
        return if session[:attribution].present?

        tracked = params.permit(*ATTRIBUTION_PARAMS).to_h.compact_blank
        session[:attribution] = tracked.merge(
          "landing_page" => request.fullpath.truncate(255),
          "referrer" => request.referer.to_s.truncate(255).presence
        ).compact
      end

      def use_tenant_time_zone(&)
        Time.use_zone(current_tenant.time_zone, &)
      end
  end
end
