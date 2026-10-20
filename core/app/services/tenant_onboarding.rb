# Onboards a new taxi firm in one step: the firm, its owner login, default
# tariffs, and the regional template of places and fixed-price routes.
# This is what "add a firm without building a new service" means in practice.
class TenantOnboarding
  Result = Data.define(:tenant, :owner, :errors) do
    def success? = errors.empty?
  end

  REGIONS_DIR = Rails.root.join("config/regions")

  def self.regions
    Dir[REGIONS_DIR.join("*.yml")].map { |path| File.basename(path, ".yml") }.sort
  end

  # Adds the region's places a firm does not have yet (matched by name), so
  # firms onboarded before a template grew still get every locality. Existing
  # places, prices and routes are left exactly as the firm set them.
  def self.sync_places(tenant, region)
    raise ArgumentError, "unknown region #{region}" unless regions.include?(region)

    template = YAML.safe_load_file(REGIONS_DIR.join("#{region}.yml"))
    known = tenant.places.pluck(:name)
    position = tenant.places.maximum(:position).to_i
    template.fetch("places", []).reject { |attrs| known.include?(attrs.fetch("name")) }.map do |attrs|
      tenant.places.create!(attrs.merge("position" => position += 1))
    end
  end

  def initialize(tenant_attrs:, owner_attrs:, region: nil)
    @tenant_attrs = tenant_attrs
    @owner_attrs = owner_attrs
    @region = region.presence
  end

  def call
    tenant = Tenant.new(@tenant_attrs)
    owner = nil

    ActiveRecord::Base.transaction do
      template = load_region
      apply_region_defaults(tenant, template) if template
      tenant.save!
      owner = tenant.users.create!(@owner_attrs.merge(role: "owner"))
      create_tariffs(tenant, template)
      create_places_and_routes(tenant, template) if template
    end

    Result.new(tenant: tenant, owner: owner, errors: [])
  rescue ActiveRecord::RecordInvalid => e
    Result.new(tenant: tenant, owner: owner, errors: e.record.errors.full_messages)
  end

  private
    def load_region
      return nil unless @region
      raise ArgumentError, "unknown region #{@region}" unless self.class.regions.include?(@region)

      YAML.safe_load_file(REGIONS_DIR.join("#{@region}.yml"))
    end

    # Region values fill in whatever the admin did not type explicitly.
    def apply_region_defaults(tenant, template)
      given = @tenant_attrs.to_h.stringify_keys.compact_blank.keys
      template.fetch("tenant_defaults", {}).each do |key, value|
        tenant.public_send(:"#{key}=", value) unless given.include?(key)
      end
    end

    def create_tariffs(tenant, template)
      tariffs = template&.fetch("tariffs", nil) || {
        "standard" => { "base_fare_cents" => 800, "per_km_cents" => 380, "minimum_fare_cents" => 2000 }
      }
      VehicleCategory::ALL.each do |category|
        attrs = tariffs.fetch(category, tariffs.fetch("standard"))
        tenant.tariffs.create!(attrs.merge("vehicle_category" => category))
      end
    end

    def create_places_and_routes(tenant, template)
      places = template.fetch("places", []).each_with_index.to_h do |attrs, index|
        place = tenant.places.create!(attrs.merge("position" => index))
        [ place.name, place ]
      end

      template.fetch("fixed_routes", []).each do |route|
        route.fetch("prices").each do |category, francs|
          tenant.fixed_routes.create!(
            origin_place: places.fetch(route.fetch("from")),
            destination_place: places.fetch(route.fetch("to")),
            vehicle_category: category,
            price_cents: (francs * 100).round,
            bidirectional: route.fetch("bidirectional", true)
          )
        end
      end
    end
end
