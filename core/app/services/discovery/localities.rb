module Discovery
  # One landing page per real place the firm serves: "Taxi Vaduz", "Taxi
  # Bendern", "Taxi Flughafen Zürich - Liechtenstein".
  #
  # Every page carries facts specific to that place (prices from it, travel
  # times, the places around it). That is what makes it useful to a person
  # and to a search engine. Google penalises near-identical "city pages"
  # mass-produced per keyword, so we build one page per place, never one per
  # search phrase; Discovery::Keywords maps the phrases onto these pages.
  class Localities
    NEARBY = 6
    LOCAL_HOPS = 4

    def initialize(tenant)
      @tenant = tenant
    end

    def all
      @all ||= @tenant.places.order(:position, :name).to_a.reject(&:umbrella?)
    end

    def find(slug) = all.find { |place| place.slug == slug }

    def local?(place) = @tenant.within_service_area?(place.to_point)
    def local = all.select { |place| local?(place) }
    def remote = all.reject { |place| local?(place) }

    def nearby(place)
      (all - [ place ]).select { |other| local?(other) == local?(place) }
                       .min_by(NEARBY) { |other| distance(place, other) }
    end

    # Rows for the price table: where people go from this place.
    def price_rows(place)
      destinations_for(place).filter_map do |destination|
        quote = cached_quote(place, destination)
        { place: destination, **quote } if quote[:price_cents]
      end
    end

    private
      # From a local place: the long-distance destinations (airports, fixed
      # routes) plus the nearest villages. From a remote place: every locality
      # in the firm's area, because that is where those riders are going.
      def destinations_for(place)
        if local?(place)
          far = remote.select { |other| other.airport? || fixed_route_endpoint_ids.include?(other.id) }
          near = local.reject { |other| other == place || other.station? }
                      .min_by(LOCAL_HOPS) { |other| distance(place, other) }
          far + near
        else
          local.select { |other| other.kind == "town" }
        end
      end

      def fixed_route_endpoint_ids
        @fixed_route_endpoint_ids ||= @tenant.fixed_routes.active.pluck(:origin_place_id, :destination_place_id).flatten.uniq
      end

      # Quoted at midday tomorrow: the plain day rate, no night surcharge.
      # Cached until the firm changes prices, places or tariffs.
      def cached_quote(from, to)
        key = [ "locality-quote", @tenant.id, from.id, to.id, cache_version ].join(":")
        Rails.cache.fetch(key, expires_in: 1.day) do
          quote = Pricing::Quoter.new(@tenant).quote(pickup: from.to_point, dropoff: to.to_point,
                                                      pickup_at: @tenant.now.tomorrow.change(hour: 12))
          {
            price_cents: (quote.price_cents if quote.priced?),
            fixed: quote.source == "fixed_route",
            estimated: quote.estimated? || quote.source == "tariff",
            duration_min: quote.duration_s && (quote.duration_s / 60.0).round
          }
        end
      end

      def cache_version
        @cache_version ||= [
          @tenant.updated_at, @tenant.places.maximum(:updated_at),
          @tenant.fixed_routes.maximum(:updated_at), @tenant.tariffs.maximum(:updated_at)
        ].map(&:to_i).join("-")
      end

      def distance(a, b) = Geo.distance_m(a.lat.to_f, a.lng.to_f, b.lat.to_f, b.lng.to_f)
  end
end
