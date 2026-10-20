require "test_helper"

# "Taxi Vaduz", "Taxi Bendern", "Taxi Zurich Airport": every place in and
# around Liechtenstein has a page that answers the search.
class LocalitiesTest < ActionDispatch::IntegrationTest
  MUNICIPALITIES = %w[Vaduz Schaan Triesen Balzers Triesenberg Eschen Mauren Ruggell Gamprin Schellenberg Planken].freeze

  setup do
    @tenant = create_tenant(slug: "taxi-fl")
  end

  test "the Liechtenstein template covers every municipality and the villages people search for" do
    names = @tenant.places.pluck(:name)
    assert_empty MUNICIPALITIES - names
    assert_empty %w[Bendern Nendeln Schaanwald Mäls Malbun Steg] - names
  end

  test "a village page answers 'taxi bendern'" do
    get "/taxi-fl/taxi/bendern"
    assert_response :success
    assert_select "title", /\ATaxi Bendern/
    assert_select "h1", "Taxi Bendern"
    assert_select "a[href=?]", "/taxi-fl/now?from=#{place(@tenant, "Bendern").id}"

    zurich = css_select("tbody tr").find { |row| row.text.include?("Flughafen Zürich") }
    assert zurich, "price table lists Zurich Airport"
    assert_includes zurich.text, "CHF 290"
    assert_includes zurich.text, "Festpreis"

    assert_select "link[rel=canonical][href=?]", "http://localhost:3000/taxi-fl/taxi/bendern"
    assert_select "link[rel=alternate][hreflang=en][href=?]", "http://localhost:3000/taxi-fl/taxi/bendern?lang=en"
    assert_select ".chips a", minimum: 3 # nearby places
    faq = JSON.parse(css_select("script[type='application/ld+json']").last.text)["@graph"].find { |node| node["@type"] == "FAQPage" }
    assert faq["mainEntity"].any? { |q| q["name"].include?("Bendern") }
  end

  test "URLs stay the same in every language" do
    get "/taxi-fl/taxi/maels", params: { lang: "en" }
    assert_response :success
    assert_select "h1", "Taxi Mäls"
    assert_select "link[rel=canonical][href=?]", "http://localhost:3000/taxi-fl/taxi/maels?lang=en"
  end

  test "an airport page is a transfer page into Liechtenstein" do
    get "/taxi-fl/taxi/flughafen-zuerich"
    assert_response :success
    assert_select "h1", "Taxi Flughafen Zürich – Liechtenstein"
    vaduz = css_select("tbody tr").find { |row| row.text.include?("Vaduz") }
    assert_includes vaduz.text, "CHF 290"
    assert_select "h3", /Flug Verspätung/
  end

  test "unknown places and the catch-all area have no page" do
    get "/taxi-fl/taxi/atlantis"
    assert_response :not_found
    get "/taxi-fl/taxi/liechtenstein"
    assert_response :not_found
  end

  test "localities are linked from the booking page and listed for crawlers and assistants" do
    get "/taxi-fl"
    assert_select "a[href='/taxi-fl/taxi/bendern']", "Taxi Bendern"

    get "/taxi-fl/sitemap.xml"
    MUNICIPALITIES.each do |name|
      assert_includes response.body, "/taxi-fl/taxi/#{name.parameterize}</loc>"
    end

    get "/taxi-fl/llms.txt"
    assert_includes response.body, "[Taxi Bendern](http://localhost:3000/taxi-fl/taxi/bendern) (also: Bendern Gamprin)"
    assert_includes response.body, "[Flughafen Zürich](http://localhost:3000/taxi-fl/taxi/flughafen-zuerich)"

    get "/taxi-fl/discovery.json"
    assert json["localities"].any? { |l| l["name"] == "Schaan" && l["in_service_area"] }
  end

  test "search phrases map to the page that answers them" do
    keywords = Discovery::Keywords.new(@tenant).all.to_h { |k| [ k.phrase, k.url ] }
    base = "http://localhost:3000/taxi-fl"

    assert_equal "#{base}/taxi/vaduz", keywords["taxi vaduz"]
    assert_equal "#{base}/taxi/bendern", keywords["taxi bendern"]
    assert_equal "#{base}/taxi/schaan", keywords["taxi schaan zurich airport"]
    assert_equal "#{base}/taxi/triesen", keywords["taxi von triesen nach flughafen zürich"]
    assert_equal "#{base}/taxi/flughafen-zuerich", keywords["taxi zurich airport liechtenstein"]
    assert_equal "#{base}/taxi/flughafen-zuerich", keywords["taxi zrh vaduz"]
    assert_equal "#{base}/now", keywords["taxi sofort liechtenstein"]
    assert_equal base, keywords["taxi liechtenstein"]
  end

  test "the admin downloads the keywords for Google Ads and adds missing localities" do
    bare = create_tenant(slug: "taxi-bare", region: nil)
    sign_in create_platform_admin

    get "/admin/tenants/#{@tenant.id}/discovery.csv"
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body)
    assert_equal [ "Ad group", "Keyword", "Criterion Type", "Final URL" ], rows.first
    bendern = rows.find { |row| row[1] == "taxi bendern" }
    assert_equal "http://localhost:3000/taxi-fl/taxi/bendern?utm_campaign=taxi-bendern&utm_medium=cpc&utm_source=google", bendern[3]

    post "/admin/tenants/#{bare.id}/discovery/sync_places", params: { region: "liechtenstein" }
    assert_redirected_to "/admin/tenants/#{bare.id}/discovery"
    assert_empty MUNICIPALITIES - bare.places.pluck(:name)

    assert_no_difference -> { bare.places.count } do
      post "/admin/tenants/#{bare.id}/discovery/sync_places", params: { region: "liechtenstein" }
    end

    get "/admin/tenants/#{@tenant.id}/discovery"
    assert_select "summary", /Suchbegriffe/
  end
end
