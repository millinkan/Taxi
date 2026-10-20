require "test_helper"

# How a firm is found by Google and AI assistants, and how the admin pushes it.
class DiscoveryTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(slug: "taxi-find", google_business_url: "https://maps.app.goo.gl/abc")
    @route = @tenant.fixed_routes.active.joins(:destination_place).find_by!(places: { name: "Flughafen Zürich" })
  end

  def json_ld
    JSON.parse(css_select("script[type='application/ld+json']").first.text)
  end

  test "public pages carry schema.org markup with a taxi-now order action" do
    get "/taxi-find"
    graph = json_ld["@graph"]
    business = graph.find { |node| node["@type"] == "LocalBusiness" }
    assert_equal @tenant.name, business["name"]
    assert_equal "+4232300000", business["telephone"]
    assert_includes business["sameAs"], "https://maps.app.goo.gl/abc"

    order = business["potentialAction"].find { |action| action["@type"] == "OrderAction" }
    assert_equal "http://localhost:3000/taxi-find/now?pickup={pickup}&dropoff={dropoff}", order.dig("target", "urlTemplate")

    service = graph.find { |node| node["@type"] == "TaxiService" }
    assert service["offers"].any? { |offer| offer["name"].include?("Flughafen Zürich") && offer["priceCurrency"] == "CHF" }
  end

  test "private pages carry no markup" do
    booking = create_booking(@tenant)
    get "/taxi-find/b/#{booking.public_token}"
    assert_select "script[type='application/ld+json']", 0
  end

  test "every fixed-price route has a landing page" do
    get "/taxi-find/routes/#{@route.to_param}"
    assert_response :success
    assert_select "h1", /Flughafen Zürich/
    assert_select "link[rel=canonical][href=?]", "http://localhost:3000/taxi-find/routes/#{@route.to_param}"
    assert_select "a[href=?]", "/taxi-find/now?from=#{@route.origin_place_id}&to=#{@route.destination_place_id}"

    get "/taxi-find/routes/#{@route.id}-old-name"
    assert_redirected_to "/taxi-find/routes/#{@route.to_param}"
    assert_response :moved_permanently

    other = create_tenant(slug: "taxi-elsewhere")
    get "/taxi-elsewhere/routes/#{@route.to_param}"
    assert_response :not_found
    assert other
  end

  test "sitemap, llms.txt and the JSON feed describe the firm" do
    get "/taxi-find/sitemap.xml"
    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, "<loc>http://localhost:3000/taxi-find/now</loc>"
    assert_includes response.body, "<loc>http://localhost:3000/taxi-find/routes/#{@route.to_param}</loc>"

    get "/taxi-find/llms.txt"
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "# #{@tenant.name}"
    assert_includes response.body, "[Taxi now](http://localhost:3000/taxi-find/now?utm_medium=discovery&utm_source=ai_assistant)"
    assert_match(/Flughafen Zürich\]\(.+\): CHF \d+/, response.body)

    get "/taxi-find/discovery.json"
    feed = json
    assert_equal true, feed.dig("actions", "taxi_now", "available")
    assert_includes feed.dig("actions", "taxi_now", "url_template"), "pickup={pickup}"
    assert feed["fixed_prices"].any? { |price| price["to"] == "Flughafen Zürich" || price["from"] == "Flughafen Zürich" }
  end

  test "taxi now disappears from discovery when switched off" do
    @tenant.update!(asap_enabled: false)
    get "/taxi-find/sitemap.xml"
    assert_not_includes response.body, "/taxi-find/now<"
    get "/taxi-find/llms.txt"
    assert_not_includes response.body, "[Taxi now]"
  end

  test "robots.txt hides private pages and lists the sitemaps" do
    get "/robots.txt"
    assert_includes response.body, "Disallow: /d/"
    assert_includes response.body, "Sitemap: http://localhost:3000/taxi-find/sitemap.xml"
    rules = response.body.split("\n\n").first
    %w[OAI-SearchBot PerplexityBot Claude-SearchBot Googlebot Bingbot].each do |agent|
      assert_includes rules, "User-agent: #{agent}"
    end

    @tenant.update!(custom_domain: "taxi-find.example")
    host! "taxi-find.example"
    get "/robots.txt"
    assert_equal [ "Sitemap: https://taxi-find.example/sitemap.xml" ], response.body.lines.grep(/Sitemap/).map(&:chomp)

    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://taxi-find.example/now</loc>"
  end

  test "the IndexNow key is served for ownership checks" do
    get "/indexnow-key.txt"
    assert_equal Discovery.indexnow_key, response.body
    assert_match(/\A\h{32}\z/, response.body)
  end

  test "the admin sees readiness and pushes the firm" do
    sign_in create_platform_admin
    get "/admin/tenants/#{@tenant.id}/discovery"
    assert_response :success
    assert_select ".checklist li.is-ok", minimum: 5
    assert_select "a[href=?]", "http://localhost:3000/taxi-find/now?utm_medium=business_profile&utm_source=google"

    assert_enqueued_jobs 2, only: DiscoveryPushJob do
      post "/admin/tenants/#{@tenant.id}/discovery"
    end
    assert_redirected_to "/admin/tenants/#{@tenant.id}/discovery"
    assert_equal %w[google indexnow], @tenant.discovery_pushes.pluck(:channel).sort
  end

  test "firm owners cannot push" do
    sign_in owner_of(@tenant)
    post "/admin/tenants/#{@tenant.id}/discovery"
    assert_response :forbidden
  end
end
