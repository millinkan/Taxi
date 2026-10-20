module Discovery
  # Everything search engines and AI assistants are told about one firm, built
  # from the firm's live settings and fixed prices. One source feeds all
  # formats, so the schema.org markup, the JSON feed, llms.txt and the sitemap
  # can never disagree with each other or with the booking page.
  #
  # Every format carries the "Taxi now" link, so a person who asks Google or
  # an assistant for a taxi lands on a page that orders one.
  class Profile
    include PriceFormatting

    MAX_OFFERS = 60
    # Links handed to AI assistants are tagged so bookings they bring show up
    # in the firm's attribution (utm_source) like any other campaign.
    AI_UTM = { utm_source: "ai_assistant", utm_medium: "discovery" }.freeze
    GOOGLE_PROFILE_UTM = { utm_source: "google", utm_medium: "business_profile" }.freeze

    def initialize(tenant)
      @tenant = tenant
      @urls = TenantUrls.new(tenant)
    end

    attr_reader :tenant, :urls

    def phone = @tenant.public_phone.presence || @tenant.dispatcher_phone

    # One representative per pair of places (the cheapest category); the
    # route page lists every category for that pair.
    def route_pages
      @route_pages ||= @tenant.fixed_routes.active.includes(:origin_place, :destination_place)
                              .order(:price_cents).to_a
                              .uniq { |route| [ route.origin_place_id, route.destination_place_id ] }
    end

    def localities = @localities ||= Localities.new(@tenant)

    def offers
      @offers ||= @tenant.fixed_routes.active.includes(:origin_place, :destination_place)
                         .order(:price_cents).limit(MAX_OFFERS).to_a
    end

    # "/now?pickup={pickup}&dropoff={dropoff}" with optional tracking params.
    # Built by hand: to_query would escape the template braces.
    def now_url_template(utm = {})
      query = utm.to_query
      "#{@urls.now_page}?#{[ query.presence, "pickup={pickup}&dropoff={dropoff}" ].compact.join("&")}"
    end

    # --- schema.org (embedded in every public page) --------------------------

    def json_ld
      business_id = "#{@urls.public_base}#business"
      business = {
        "@type" => "LocalBusiness",
        "@id" => business_id,
        "additionalType" => "https://schema.org/TaxiService",
        "name" => @tenant.name,
        "legalName" => @tenant.legal_name.presence,
        "url" => @urls.booking_page,
        "telephone" => phone,
        "email" => @tenant.email.presence,
        "logo" => @tenant.logo_url.presence,
        "image" => @tenant.logo_url.presence,
        "openingHours" => @tenant.opening_hours,
        "currenciesAccepted" => @tenant.currency,
        "paymentAccepted" => "Cash, Credit Card",
        "areaServed" => area_served,
        "geo" => geo,
        "sameAs" => [ @tenant.website_url, @tenant.google_business_url ].compact_blank.presence,
        "potentialAction" => actions
      }.compact

      service = {
        "@type" => "TaxiService",
        "@id" => "#{@urls.public_base}#taxi",
        "name" => "Taxi #{@tenant.home_area_label}",
        "provider" => { "@id" => business_id },
        "areaServed" => [ area_served, *localities.local.map { |place| place_node(place) } ],
        "availableChannel" => {
          "@type" => "ServiceChannel",
          "serviceUrl" => @urls.now_page,
          "servicePhone" => phone && { "@type" => "ContactPoint", "telephone" => phone }
        }.compact,
        "offers" => offers.map { |route| offer(route) }.presence,
        "potentialAction" => actions
      }.compact

      { "@context" => "https://schema.org", "@graph" => [ business, service ] }
    end

    # --- discovery.json (the feed for AI assistants and partners) ------------

    def feed
      {
        schema_version: 1,
        generated_at: Time.current.iso8601,
        firm: {
          name: @tenant.name,
          legal_name: @tenant.legal_name.presence,
          licence_number: @tenant.licence_number.presence,
          phone: phone,
          email: @tenant.email.presence,
          website: @tenant.website_url.presence,
          google_business_profile: @tenant.google_business_url.presence,
          home_area: @tenant.home_area_label,
          service_center: @tenant.service_center && { lat: @tenant.service_center_lat.to_f, lng: @tenant.service_center_lng.to_f },
          service_radius_km: @tenant.service_radius_km,
          opening_hours: @tenant.opening_hours,
          languages: Tenant::LOCALES,
          currency: @tenant.currency,
          payment: "in the car, cash or card"
        },
        actions: {
          taxi_now: {
            available: @tenant.asap_enabled?,
            url: @urls.now_page(AI_UTM),
            url_template: now_url_template(AI_UTM),
            how_it_works: "The customer sends pickup, destination and mobile number. The dispatcher replies by SMS " \
                          "with the arrival time within #{@tenant.asap_response_minutes} minutes, or the customer is told no car is free."
          },
          book_ahead: {
            url: @urls.booking_page(AI_UTM),
            min_lead_minutes: @tenant.min_lead_minutes,
            max_advance_days: @tenant.max_advance_days
          },
          call: { phone: phone },
          empty_leg_deals: { url: @urls.deals_page }
        },
        fixed_prices: offers.map do |route|
          {
            from: route.origin_place.name,
            to: route.destination_place.name,
            both_directions: route.bidirectional?,
            vehicle_category: route.vehicle_category,
            price: route.price_cents / 100.0,
            price_text: format_price(route.price_cents, @tenant.currency),
            currency: @tenant.currency,
            url: @urls.route_page(route_pages.find { |page| same_pair?(page, route) } || route)
          }
        end,
        localities: localities.all.map do |place|
          { name: place.name, also_known_as: place.alias_list.presence, kind: place.kind,
            in_service_area: localities.local?(place), url: @urls.locality_page(place) }.compact
        end,
        links: { sitemap: @urls.sitemap, llms_txt: @urls.llms_txt }
      }
    end

    # schema.org node for one locality; also used on its landing page.
    def place_node(place)
      {
        "@type" => place.airport? ? "Airport" : "Place",
        "name" => place.name,
        "alternateName" => place.alias_list.presence,
        "url" => @urls.locality_page(place),
        "geo" => { "@type" => "GeoCoordinates", "latitude" => place.lat.to_f, "longitude" => place.lng.to_f }
      }.compact
    end

    # --- llms.txt (plain-language summary for language models) ---------------

    def llms_txt
      lines = []
      lines << "# #{@tenant.name}"
      lines << ""
      lines << "> Local taxi firm for #{@tenant.home_area_label}. Taxi now, pre-booked rides and fixed airport " \
               "prices. Order online or call #{display_phone}. Payment in the car (cash or card)."
      lines << ""
      lines << "## Order a taxi"
      if @tenant.asap_enabled?
        lines << "- [Taxi now](#{@urls.now_page(AI_UTM)}): order a taxi for right now. The dispatcher confirms the " \
                 "arrival time by SMS within #{@tenant.asap_response_minutes} minutes. Link template with the " \
                 "customer's addresses: #{now_url_template(AI_UTM)}"
      end
      lines << "- [Book ahead](#{@urls.booking_page(AI_UTM)}): from #{@tenant.min_lead_minutes} minutes up to " \
               "#{@tenant.max_advance_days} days in advance, live price, SMS confirmation."
      lines << "- Phone: #{display_phone}" if phone
      lines << ""
      if route_pages.any?
        lines << "## Fixed prices"
        route_pages.each do |route|
          lines << "- [#{route.label}](#{@urls.route_page(route)}): #{format_price(route.price_cents, @tenant.currency)}"
        end
        lines << ""
      end
      if localities.local.any?
        lines << "## Areas served (taxi now and booked rides)"
        localities.local.each do |place|
          aka = place.alias_list.presence && " (also: #{place.alias_list.join(", ")})"
          lines << "- [Taxi #{place.name}](#{@urls.locality_page(place)})#{aka}"
        end
        lines << ""
      end
      if localities.remote.any?
        lines << "## Transfers to and from #{@tenant.home_area_label}"
        localities.remote.each do |place|
          lines << "- [#{place.name}](#{@urls.locality_page(place)})"
        end
        lines << ""
      end
      lines << "## Facts"
      lines << "- Service area: #{@tenant.home_area_label}, about #{@tenant.service_radius_km} km around the base"
      lines << "- Opening hours: #{@tenant.opening_hours}"
      lines << "- Languages: German, English"
      lines << "- Licence: #{@tenant.licence_number}" if @tenant.licence_number.present?
      lines << "- [Empty-leg deals](#{@urls.deals_page}): discounted rides on cars returning empty"
      lines << ""
      lines << "## Machine-readable"
      lines << "- [discovery.json](#{@urls.discovery_feed}): prices, booking links and contact as JSON"
      lines << "- [sitemap.xml](#{@urls.sitemap})"
      lines.join("\n") + "\n"
    end

    # --- sitemap.xml ----------------------------------------------------------

    # lastmod is what automatic pushes compare against, so it has to move only
    # when the page's content does.
    def sitemap_entries
      entries = [
        { loc: @urls.booking_page, lastmod: @tenant.updated_at, priority: "1.0" },
        ({ loc: @urls.now_page, lastmod: @tenant.updated_at, priority: "0.9" } if @tenant.asap_enabled?),
        { loc: @urls.deals_page, lastmod: [ @tenant.updated_at, @tenant.empty_legs.maximum(:updated_at) ].compact.max, priority: "0.5" }
      ].compact
      entries +
        localities.all.map do |place|
          { loc: @urls.locality_page(place), lastmod: [ place.updated_at, route_changes[place.id] ].compact.max,
            priority: localities.local?(place) ? "0.9" : "0.7" }
        end +
        route_pages.map { |route| { loc: @urls.route_page(route), lastmod: route.updated_at, priority: "0.8" } }
    end

    def urls_to_push = sitemap_entries.pluck(:loc)

    # --- links the firm pastes into its Google Business Profile ---------------

    def google_profile_links
      {
        website: @urls.booking_page(GOOGLE_PROFILE_UTM),
        order: @urls.now_page(GOOGLE_PROFILE_UTM),
        booking: @urls.booking_page(GOOGLE_PROFILE_UTM.merge(utm_campaign: "book"))
      }
    end

    # --- readiness checklist for the admin ------------------------------------

    def checks
      [
        [ :active, @tenant.active? ],
        [ :phone, phone.present? ],
        [ :dispatcher_phone, @tenant.dispatcher_phone.present? ],
        [ :taxi_now, @tenant.asap_enabled? ],
        [ :service_area, @tenant.service_center.present? ],
        [ :fixed_prices, route_pages.any? ],
        [ :localities, localities.local.size >= 5 ],
        [ :google_business, @tenant.google_business_url.present? ],
        [ :reviews, @tenant.google_review_url.present? ]
      ].map { |key, ok| { key: key, ok: ok } }
    end

    def ready? = checks.first(3).all? { |check| check[:ok] }

    private
      def display_phone = phone && PhoneNumber.display(phone)

      # Latest price change per place: a locality page lists the prices of
      # the routes starting or ending there.
      def route_changes
        @route_changes ||= begin
          routes = @tenant.fixed_routes
          routes.group(:origin_place_id).maximum(:updated_at)
                .merge(routes.group(:destination_place_id).maximum(:updated_at)) { |_, a, b| [ a, b ].max }
        end
      end

      def same_pair?(a, b)
        a.origin_place_id == b.origin_place_id && a.destination_place_id == b.destination_place_id
      end

      def area_served
        if @tenant.service_center
          {
            "@type" => "GeoCircle",
            "name" => @tenant.home_area_label,
            "geoMidpoint" => geo,
            "geoRadius" => @tenant.service_radius_km * 1000
          }
        else
          { "@type" => "AdministrativeArea", "name" => @tenant.home_area_label }
        end
      end

      def geo
        return nil unless @tenant.service_center

        { "@type" => "GeoCoordinates", "latitude" => @tenant.service_center_lat.to_f,
          "longitude" => @tenant.service_center_lng.to_f }
      end

      def actions
        list = []
        if @tenant.asap_enabled?
          list << {
            "@type" => "OrderAction",
            "name" => "Taxi now",
            "target" => {
              "@type" => "EntryPoint",
              "urlTemplate" => now_url_template,
              "actionPlatform" => %w[https://schema.org/DesktopWebPlatform https://schema.org/MobileWebPlatform]
            }
          }
        end
        list << {
          "@type" => "ReserveAction",
          "name" => "Book a taxi",
          "target" => { "@type" => "EntryPoint", "urlTemplate" => @urls.booking_page }
        }
        list
      end

      def offer(route)
        {
          "@type" => "Offer",
          "name" => "#{route.label} (#{route.vehicle_category})",
          "price" => format("%.2f", route.price_cents / 100.0),
          "priceCurrency" => @tenant.currency,
          "url" => @urls.route_page(route_pages.find { |page| same_pair?(page, route) } || route)
        }
      end
  end
end
