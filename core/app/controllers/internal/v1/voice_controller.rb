module Internal
  module V1
    # Everything the voice agent needs to know about a firm, looked up by the
    # phone number that was called.
    class VoiceController < BaseController
      def lookup
        firm = Tenant.active.for_voice_number(params.require(:number))
        return render(json: { ok: false, error: "unknown_number" }, status: :not_found) unless firm

        render json: { ok: true, tenant: payload(firm) }
      end

      private
        def payload(firm)
          {
            id: firm.id,
            name: firm.name,
            slug: firm.slug,
            time_zone: firm.time_zone,
            now_local: firm.now.iso8601,
            currency: firm.currency,
            default_locale: firm.default_locale,
            voice_agent_enabled: firm.voice_agent_enabled?,
            voice_greeting: firm.voice_greeting.presence,
            dispatcher_phone: firm.dispatcher_phone,
            public_phone: firm.public_phone,
            home_area_label: firm.home_area_label,
            min_lead_minutes: firm.min_lead_minutes,
            max_advance_days: firm.max_advance_days,
            free_cancellation_hours: firm.free_cancellation_hours,
            asap_enabled: firm.asap_enabled?,
            asap_response_minutes: firm.asap_response_minutes,
            booking_url: TenantUrls.new(firm).booking_page,
            fleet: VehicleCategory::ALL.map { |c| { category: c, seats: VehicleCategory::DEFAULT_SEATS[c] } },
            places: firm.places.order(:position, :name).map do |place|
              { id: place.id, name: place.name, kind: place.kind, aliases: place.alias_list }
            end
          }
        end
    end
  end
end
