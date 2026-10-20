module Discovery
  # Every search phrase the firm's pages answer, with the page that answers
  # it: "taxi vaduz" -> /taxi/vaduz, "taxi schaan zurich airport" ->
  # /taxi/schaan (whose price table lists Zurich Airport), "taxi sofort
  # liechtenstein" -> /now.
  #
  # Shown to the admin as proof of coverage and exported for Google Ads, so
  # paid search lands on the same pages organic search does.
  class Keywords
    Keyword = Data.define(:group, :phrase, :url)

    def initialize(tenant)
      @tenant = tenant
      @urls = TenantUrls.new(tenant)
      @localities = Localities.new(tenant)
      @home = tenant.home_area_label
    end

    def all
      @all ||= (generic + @localities.local.flat_map { |place| for_local(place) } +
                @localities.remote.flat_map { |place| for_remote(place) })
               .uniq(&:phrase)
    end

    def groups = all.group_by(&:group)

    private
      def generic
        group = "#{@home} (allgemein)"
        umbrella_aliases = @tenant.places.select(&:umbrella?).flat_map(&:alias_list)
        list = ([ @home ] + umbrella_aliases).flat_map do |name|
          [ "taxi #{name}", "taxi service #{name}", "flughafentransfer #{name}", "airport transfer #{name}" ]
        end.map { |phrase| keyword(group, phrase, @urls.booking_page) }

        if @tenant.asap_enabled?
          list += [ "taxi sofort #{@home}", "taxi jetzt #{@home}", "taxi now #{@home}", "taxi in der nähe #{@home}" ]
                  .map { |phrase| keyword(group, phrase, @urls.now_page) }
        end
        list
      end

      # "taxi bendern", "taxi sofort bendern", "taxi bendern zürich flughafen".
      def for_local(place)
        group = "Taxi #{place.name}"
        url = @urls.locality_page(place)
        names = [ place.name, *place.alias_list ]

        list = names.map { |name| keyword(group, "taxi #{name}", url) }
        list << keyword(group, "taxi sofort #{place.name}", url) if @tenant.asap_enabled?
        list += far_destinations.flat_map do |destination|
          destination_names(destination).flat_map do |target|
            [ keyword(group, "taxi #{place.name} #{target}", url),
              keyword(group, "taxi von #{place.name} nach #{target}", url) ]
          end
        end
        list
      end

      # "taxi zürich flughafen liechtenstein", "taxi zrh vaduz".
      def for_remote(place)
        group = "#{place.name} - #{@home}"
        url = @urls.locality_page(place)
        destination_names(place, all_aliases: true).flat_map do |name|
          [ keyword(group, "taxi #{name} #{@home}", url), keyword(group, "taxi von #{name} nach #{@home}", url) ] +
            @localities.local.select { |town| town.kind == "town" }.map { |town| keyword(group, "taxi #{name} #{town.name}", url) }
        end
      end

      def far_destinations
        @far_destinations ||= @localities.remote.select { |place| place.airport? || place.kind == "resort" || place.kind == "town" }
      end

      # The place's own name plus the English or short form people type
      # ("Zurich Airport", "ZRH"); every alias only where volume is low anyway.
      def destination_names(place, all_aliases: false)
        aliases = place.alias_list
        aliases = aliases.select { |name| name.match?(/airport|\A[A-Z]{3}\z/i) } unless all_aliases
        [ place.name, *aliases ].uniq
      end

      def keyword(group, phrase, url) = Keyword.new(group: group, phrase: phrase.downcase.squish, url: url)
  end
end
