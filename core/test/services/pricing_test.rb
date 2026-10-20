require "test_helper"

class PricingTest < ActiveSupport::TestCase
  setup do
    @tenant = create_tenant
    @quoter = Pricing::Quoter.new(@tenant)
    @resolver = Geocoding::Resolver.new(@tenant)
  end

  def quote(from, to, at: local_time(@tenant), category: "standard")
    @quoter.quote(pickup: @resolver.resolve(from), dropoff: @resolver.resolve(to), pickup_at: at, vehicle_category: category)
  end

  test "airport transfers use the fixed price, in both directions" do
    there = quote("Vaduz", "Flughafen Zürich")
    back = quote("ZRH", "Schaan")

    assert_equal "fixed_route", there.source
    assert_equal 29_000, there.price_cents
    assert_equal 29_000, back.price_cents
    assert_not there.estimated?
  end

  test "fixed prices are per vehicle category" do
    assert_equal 38_000, quote("Vaduz", "Flughafen Zürich", category: "van").price_cents
  end

  test "local trips use the metered tariff, rounded to the franc" do
    result = quote("Vaduz", "Bahnhof Buchs SG", at: local_time(@tenant, hour: 14))
    assert_equal "tariff", result.source
    tariff = @tenant.tariff_for("standard")
    km = result.distance_m / 1000.0
    expected = ((tariff.base_fare_cents + tariff.per_km_cents * km) / 100.0).round * 100
    assert_equal [ expected, tariff.minimum_fare_cents ].max, result.price_cents
  end

  test "night surcharge applies inside the night window" do
    day = quote("Vaduz", "Bahnhof Sargans", at: local_time(@tenant, hour: 14))
    night = quote("Vaduz", "Bahnhof Sargans", at: local_time(@tenant, hour: 23, min: 30))
    assert night.night
    assert_operator night.price_cents, :>, day.price_cents
  end

  test "minimum fare applies to very short trips" do
    result = quote("Vaduz", "Vaduz")
    assert_equal @tenant.tariff_for("standard").minimum_fare_cents, result.price_cents
  end

  test "unknown addresses are priced on request instead of failing" do
    result = quote("Somewhere unknown 123", "Vaduz")
    assert result.ok?
    assert result.on_request?
    assert_nil result.price_cents
  end

  test "trips touching neither end of the service area are refused" do
    result = quote("Davos", "Flughafen Zürich")
    assert_equal "outside_service_area", result.error
  end

  test "tariff night window wraps midnight" do
    tariff = Tariff.new(night_starts_at: "22:00", night_ends_at: "06:00")
    zone = ActiveSupport::TimeZone["Europe/Vaduz"]
    assert tariff.night?(zone.parse("2026-10-20 23:00"))
    assert tariff.night?(zone.parse("2026-10-20 05:59"))
    assert_not tariff.night?(zone.parse("2026-10-20 06:00"))
    assert_not tariff.night?(zone.parse("2026-10-20 12:00"))
  end
end
