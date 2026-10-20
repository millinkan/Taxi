# Vehicles, metered tariffs, well-known places and fixed-price routes.
# Money is always stored in minor units (Rappen / cents) as integers.
class CreateFleetAndPricing < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicles do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :plate
      t.string  :category, null: false, default: "standard"
      t.integer :seats, null: false, default: 4
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    create_table :tariffs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string  :vehicle_category, null: false, default: "standard"
      t.integer :base_fare_cents, null: false, default: 0
      t.integer :per_km_cents, null: false, default: 0
      t.integer :per_minute_cents, null: false, default: 0
      t.integer :minimum_fare_cents, null: false, default: 0
      t.integer :night_surcharge_percent, null: false, default: 0
      t.string  :night_starts_at, null: false, default: "22:00"
      t.string  :night_ends_at, null: false, default: "06:00"
      t.integer :rounding_cents, null: false, default: 100

      t.timestamps
    end
    add_index :tariffs, [ :tenant_id, :vehicle_category ], unique: true

    create_table :places do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :kind, null: false, default: "other"
      t.string  :address
      t.decimal :lat, precision: 10, scale: 6, null: false
      t.decimal :lng, precision: 10, scale: 6, null: false
      t.integer :radius_m, null: false, default: 1500
      t.text    :aliases
      t.boolean :featured, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :places, [ :tenant_id, :name ], unique: true

    create_table :fixed_routes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :origin_place, null: false, foreign_key: { to_table: :places }
      t.references :destination_place, null: false, foreign_key: { to_table: :places }
      t.string  :vehicle_category, null: false, default: "standard"
      t.integer :price_cents, null: false
      t.boolean :bidirectional, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
