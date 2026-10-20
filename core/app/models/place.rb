# A well-known location the firm serves: airports, stations, towns, hotels.
# Places power quick-pick buttons, voice address matching and fixed routes.
class Place < ApplicationRecord
  include TenantOwned
  include PublishedContent

  KINDS = %w[airport station town hotel resort hospital other].freeze

  has_many :outbound_routes, class_name: "FixedRoute", foreign_key: :origin_place_id, dependent: :destroy
  has_many :inbound_routes, class_name: "FixedRoute", foreign_key: :destination_place_id, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :tenant_id }
  validates :kind, inclusion: { in: KINDS }
  validates :lat, numericality: { in: -90..90 }
  validates :lng, numericality: { in: -180..180 }
  validates :radius_m, numericality: { only_integer: true, in: 50..50_000 }

  def alias_list
    aliases.to_s.split(",").map(&:strip).compact_blank
  end

  def to_point
    Geo::Point.new(label: address.presence || name, lat: lat, lng: lng, place: self)
  end

  def covers?(point)
    point&.located? && Geo.distance_m(lat.to_f, lng.to_f, point.lat, point.lng) <= radius_m
  end

  def airport? = kind == "airport"
  def station? = kind == "station"

  # URL name for the place's public landing page: "Mäls" -> "maels". Fixed to
  # German transliteration so the URL is the same in every page language.
  def slug = name.parameterize(locale: :de)

  # Catch-all areas ("Liechtenstein", 14 km) exist for pricing; they are not
  # a locality anyone searches a taxi page for.
  def umbrella? = radius_m > 10_000

  # How well a free-text query names this place (0 = not at all). Used by the
  # web form and the voice agent: "Flughafen Zürich", "zurich airport" and
  # "ZRH" all find the same place.
  #
  #   3  exact name or alias            "ZRH"
  #   2  the name/alias appears in the query as whole words
  #                                     "Flughafen Zürich Terminal 2"
  #   1  the query appears in the name as whole words   "Zürich"
  #
  # Matching is on whole words only, so the alias "FL" never matches
  # "flughafen", and short fragments never match on their own.
  def match_score(query)
    needle = self.class.fold(query)
    return 0 if needle.length < 2

    ([ name ] + alias_list).map do |candidate|
      folded = self.class.fold(candidate)
      if folded == needle then 3
      elsif folded.length >= 4 && self.class.contains_words?(needle, folded) then 2
      elsif needle.length >= 4 && self.class.contains_words?(folded, needle) then 1
      else 0
      end
    end.max
  end

  def matches?(query) = match_score(query).positive?

  def self.fold(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def self.contains_words?(haystack, words)
    " #{haystack} ".include?(" #{words} ")
  end

  # Best match first; ties go to the more specific (smaller) place.
  def self.search(query)
    all.map { |place| [ place, place.match_score(query) ] }
       .select { |_, score| score.positive? }
       .sort_by { |place, score| [ -score, place.radius_m, place.position ] }
       .map(&:first)
  end
end
