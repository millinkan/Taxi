# Turns what a customer typed or said ("Landstrasse 10, Schaan", "Flughafen
# Zürich") into coordinates.
#
# Resolution order, cheapest and most reliable first:
#   1. explicit coordinates sent by the client
#   2. the firm's own known places (names and aliases)
#   3. the configured provider (Google, Nominatim), biased to the service area
#
# Any provider failure returns nil instead of raising: the booking is then
# taken with "price on request" rather than lost.
module Geocoding
  CACHE_TTL = 30.days

  module_function

  def provider
    case Rails.configuration.x.maps.geocoder
    when "google"    then GoogleProvider.new(Rails.configuration.x.maps.api_key)
    when "nominatim" then NominatimProvider.new(Rails.configuration.x.maps.contact_email)
    else NullProvider.new
    end
  end

  class Resolver
    def initialize(tenant, provider: Geocoding.provider)
      @tenant = tenant
      @provider = provider
    end

    def resolve(query, lat: nil, lng: nil, place_id: nil)
      if place_id.present? && (place = @tenant.places.find_by(id: place_id))
        return place.to_point.with(label: place.name)
      end

      if lat.present? && lng.present?
        point = Geo::Point.new(label: query.presence || "#{lat},#{lng}", lat: lat, lng: lng)
        return attach_place(point)
      end

      return nil if query.blank?

      label = query.to_s.squish.truncate(255)
      place = @tenant.places.search(query).first

      # "ZRH" / "Vaduz": the customer named a known place exactly.
      return place.to_point.with(label: place.name) if place && place.match_score(query) == 3

      # A street address: geocode it in full so the driver gets the exact
      # spot. The customer's own wording stays the label shown to the driver.
      if (located = lookup(query))
        return attach_place(located.with(label: label))
      end

      # Provider down or unsure: fall back to the town/place mentioned, which
      # is close enough to price the trip; the address text is kept as typed.
      place&.to_point&.with(label: label)
    end

    private
      def lookup(query)
        key = [ "geocode", @provider.class.name, @tenant.id, Place.fold(query) ].join(":")
        cached = Rails.cache.read(key)
        return Geo::Point.new(**cached.symbolize_keys) if cached

        point = @provider.geocode(query, bias: @tenant.service_center)
        Rails.cache.write(key, point.to_h.except(:place_id), expires_in: CACHE_TTL) if point
        point
      rescue HttpJson::Error => e
        Rails.logger.warn("[geocoding] #{e.message}")
        nil
      end

      # A street address inside an airport's radius should price like the airport.
      def attach_place(point)
        place = @tenant.places.to_a.select { |p| p.covers?(point) }.min_by(&:radius_m)
        place ? point.with(place: place) : point
      end
  end

  class GoogleProvider
    URL = "https://maps.googleapis.com/maps/api/geocode/json".freeze

    def initialize(api_key) = @api_key = api_key

    def geocode(query, bias: nil)
      params = { address: query, key: @api_key, language: "de", components: "country:LI|country:CH|country:AT|country:DE" }
      params[:bounds] = bounds(bias) if bias
      result = HttpJson.get(URL, params: params).fetch("results", []).first
      return nil unless result

      location = result.dig("geometry", "location")
      Geo::Point.new(label: result["formatted_address"], lat: location["lat"], lng: location["lng"])
    end

    private
      def bounds(center, delta = 0.5)
        "#{center.lat - delta},#{center.lng - delta}|#{center.lat + delta},#{center.lng + delta}"
      end
  end

  # OpenStreetMap's public geocoder. Free, but limited to one request per
  # second and requires an identifying contact. Fine for a pilot; use Google
  # or a self-hosted instance at scale (docs/OPERATIONS.md).
  class NominatimProvider
    URL = "https://nominatim.openstreetmap.org/search".freeze

    def initialize(contact_email) = @contact_email = contact_email

    def geocode(query, bias: nil)
      params = { q: query, format: "jsonv2", limit: 1, countrycodes: "li,ch,at,de", "accept-language": "de" }
      if bias
        params[:viewbox] = [ bias.lng - 0.6, bias.lat + 0.6, bias.lng + 0.6, bias.lat - 0.6 ].join(",")
      end
      headers = { "User-Agent" => "RideDesk/1.0 (#{@contact_email})" }
      result = Array(HttpJson.get(URL, params: params, headers: headers)).first
      return nil unless result

      Geo::Point.new(label: result["display_name"].to_s.split(",").first(3).join(",").strip,
                     lat: result["lat"], lng: result["lon"])
    end
  end

  class NullProvider
    def geocode(_query, bias: nil) = nil
  end
end
