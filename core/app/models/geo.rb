# Plain value objects and great-circle maths. No external calls here.
module Geo
  EARTH_RADIUS_M = 6_371_000.0

  # A resolved location: what the customer typed or picked, plus coordinates.
  Point = Data.define(:label, :lat, :lng, :place) do
    def initialize(label:, lat:, lng:, place: nil)
      super(label: label, lat: lat&.to_f, lng: lng&.to_f, place: place)
    end

    def located?
      lat.present? && lng.present?
    end

    def to_h
      { label: label, lat: lat, lng: lng, place_id: place&.id }
    end
  end

  module_function

  def distance_m(lat1, lng1, lat2, lng2)
    to_rad = Math::PI / 180
    dlat = (lat2 - lat1) * to_rad
    dlng = (lng2 - lng1) * to_rad
    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1 * to_rad) * Math.cos(lat2 * to_rad) * Math.sin(dlng / 2)**2
    2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
  end

  def point_distance_m(a, b)
    distance_m(a.lat, a.lng, b.lat, b.lng)
  end
end
