module Internal
  module V1
    # Machine-to-machine API used by the voice service. Authenticated with a
    # shared bearer token (INTERNAL_API_TOKEN). Not reachable without it, and
    # disabled entirely when no token is configured.
    class BaseController < ActionController::API
      include PriceFormatting

      before_action :authenticate!
      rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { ok: false, error: "not_found" }, status: :not_found }
      rescue_from ActionController::ParameterMissing, with: ->(e) { render json: { ok: false, error: e.message }, status: :bad_request }

      private
        def authenticate!
          expected = Rails.configuration.x.internal_api_token
          return render(json: { ok: false, error: "internal_api_disabled" }, status: :service_unavailable) if expected.blank?

          provided = request.authorization.to_s.delete_prefix("Bearer ")
          return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

          render json: { ok: false, error: "unauthorized" }, status: :unauthorized
        end

        def tenant
          @tenant ||= Tenant.active.find(params.require(:tenant_id))
        end

        def with_tenant_zone(&)
          Time.use_zone(tenant.time_zone, &)
        end

        # The voice agent sends local wall-clock times ("2026-10-20T14:30").
        # An explicit offset is honoured; a naive time is read in the firm's zone.
        def parse_local_time(value)
          return nil if value.blank?

          ActiveSupport::TimeZone[tenant.time_zone].parse(value.to_s)
        rescue ArgumentError
          nil
        end
    end
  end
end
