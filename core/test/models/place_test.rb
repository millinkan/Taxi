require "test_helper"

class PlaceTest < ActiveSupport::TestCase
  setup { @tenant = create_tenant }

  test "finds airports by name, alias and IATA code" do
    [ "Flughafen Zürich", "zurich airport", "ZRH", "Flughafen Zurich Terminal 2" ].each do |query|
      assert_equal "Flughafen Zürich", @tenant.places.search(query).first&.name, query
    end
  end

  test "short aliases never match inside longer words" do
    # Regression: the alias "FL" (Liechtenstein) used to match "Flughafen".
    assert_not place(@tenant, "Liechtenstein").matches?("Flughafen Zürich")
  end

  test "prefers the most specific place" do
    assert_equal "Vaduz", @tenant.places.search("Vaduz").first.name
    assert_equal "Schaan", @tenant.places.search("Landstrasse 10, Schaan").first.name
  end

  test "covers points inside its radius only" do
    zrh = place(@tenant, "Flughafen Zürich")
    assert zrh.covers?(Geo::Point.new(label: "x", lat: 47.4510, lng: 8.5630))
    assert_not zrh.covers?(Geo::Point.new(label: "x", lat: 47.1410, lng: 9.5209))
  end
end
