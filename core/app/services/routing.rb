# Driving distance and time between two points.
#
# If the configured provider fails we fall back to a straight-line estimate
# and flag the result as estimated, so the customer sees "approx." and the
# dispatcher confirms the final price. A routing outage never blocks a booking.
module Routing
  Route = Data.define(:distance_m, :duration_s, :estimated)

  # Rhine valley roads: ~1.3x the crow-flies distance at ~55 km/h average.
  ROAD_FACTOR = 1.3
  AVERAGE_SPEED_KMH = 55.0
  CACHE_TTL = 7.days

  module_function

  def provider
    case Rails.configuration.x.maps.routing
    when "google" then GoogleProvider.new(Rails.configuration.x.maps.api_key)
    when "osrm"   then OsrmProvider.new(Rails.configuration.x.maps.osrm_url)
    else EstimateProvider.new
    end
  end

  def route(from, to, provider: self.provider)
    return nil unless from&.located? && to&.located?

    key = [ "route", provider.class.name, from.lat.round(4), from.lng.round(4), to.lat.round(4), to.lng.round(4) ].join(":")
    cached = Rails.cache.fetch(key, expires_in: CACHE_TTL) { provider.route(from, to).to_h }
    Route.new(**cached.symbolize_keys)
  rescue HttpJson::Error, KeyError, NoMethodError => e
    Rails.logger.warn("[routing] #{provider.class.name} failed, estimating: #{e.message}")
    EstimateProvider.new.route(from, to)
  end

  class EstimateProvider
    def route(from, to)
      distance = Geo.point_distance_m(from, to) * ROAD_FACTOR
      duration = distance / (AVERAGE_SPEED_KMH * 1000 / 3600)
      Route.new(distance_m: distance.round, duration_s: duration.round, estimated: true)
    end
  end

  class GoogleProvider
    URL = "https://routes.googleapis.com/directions/v2:computeRoutes".freeze

    def initialize(api_key) = @api_key = api_key

    def route(from, to)
      body = {
        origin: { location: { latLng: { latitude: from.lat, longitude: from.lng } } },
        destination: { location: { latLng: { latitude: to.lat, longitude: to.lng } } },
        travelMode: "DRIVE",
        routingPreference: "TRAFFIC_UNAWARE"
      }
      headers = { "X-Goog-Api-Key" => @api_key, "X-Goog-FieldMask" => "routes.distanceMeters,routes.duration" }
      route = HttpJson.post_json(URL, body: body, headers: headers).fetch("routes").first
      raise KeyError, "no route" unless route

      Route.new(distance_m: route.fetch("distanceMeters"), duration_s: route.fetch("duration").to_i, estimated: false)
    end
  end

  class OsrmProvider
    def initialize(base_url) = @base_url = base_url.chomp("/")

    def route(from, to)
      url = "#{@base_url}/route/v1/driving/#{from.lng},#{from.lat};#{to.lng},#{to.lat}"
      route = HttpJson.get(url, params: { overview: "false" }).fetch("routes").first
      raise KeyError, "no route" unless route

      Route.new(distance_m: route.fetch("distance").round, duration_s: route.fetch("duration").round, estimated: false)
    end
  end
end
