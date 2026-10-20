class CreateCustomersAndBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string   :name
      t.string   :phone, null: false
      t.string   :email
      t.string   :locale, null: false, default: "de"
      t.text     :notes
      t.integer  :bookings_count, null: false, default: 0
      t.datetime :last_booked_at
      t.datetime :anonymized_at

      t.timestamps
    end
    add_index :customers, [ :tenant_id, :phone ], unique: true

    create_table :empty_legs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :source_booking # FK added below, bookings does not exist yet
      t.string   :origin_label, null: false
      t.decimal  :origin_lat, precision: 10, scale: 6, null: false
      t.decimal  :origin_lng, precision: 10, scale: 6, null: false
      t.string   :destination_label, null: false
      t.decimal  :destination_lat, precision: 10, scale: 6, null: false
      t.decimal  :destination_lng, precision: 10, scale: 6, null: false
      t.datetime :available_from, null: false
      t.datetime :available_until, null: false
      t.integer  :price_cents, null: false
      t.integer  :regular_price_cents
      t.string   :vehicle_category, null: false, default: "standard"
      t.integer  :seats, null: false, default: 4
      t.string   :status, null: false, default: "open"

      t.timestamps
    end
    add_index :empty_legs, [ :tenant_id, :status, :available_from ]

    create_table :bookings do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string   :reference, null: false
      t.string   :idempotency_key
      t.string   :status, null: false, default: "pending"
      t.string   :source, null: false, default: "web"
      t.string   :locale, null: false, default: "de"

      # Trip
      t.datetime :pickup_at, null: false
      t.string   :pickup_address, null: false
      t.decimal  :pickup_lat, precision: 10, scale: 6
      t.decimal  :pickup_lng, precision: 10, scale: 6
      t.references :pickup_place, foreign_key: { to_table: :places }
      t.string   :dropoff_address, null: false
      t.decimal  :dropoff_lat, precision: 10, scale: 6
      t.decimal  :dropoff_lng, precision: 10, scale: 6
      t.references :dropoff_place, foreign_key: { to_table: :places }
      t.integer  :passengers, null: false, default: 1
      t.integer  :luggage, null: false, default: 0
      t.string   :vehicle_category, null: false, default: "standard"
      t.string   :flight_number
      t.text     :notes
      t.text     :internal_notes

      # Price
      t.integer  :quoted_price_cents
      t.integer  :final_price_cents
      t.string   :price_source
      t.boolean  :price_estimated, null: false, default: false
      t.integer  :distance_m
      t.integer  :duration_s
      t.string   :payment_method, null: false, default: "in_car"

      # Dispatch
      t.references :driver, foreign_key: { to_table: :users }
      t.references :vehicle, foreign_key: true
      t.datetime :confirmed_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.string   :cancellation_reason
      t.datetime :dispatcher_notified_at
      t.datetime :escalated_at
      t.datetime :review_requested_at

      # Links
      t.string   :public_token, null: false
      t.string   :dispatch_token, null: false
      t.references :outbound_booking, foreign_key: { to_table: :bookings }
      t.references :empty_leg, foreign_key: true

      # Attribution: where did this booking come from?
      t.string   :utm_source
      t.string   :utm_medium
      t.string   :utm_campaign
      t.string   :gclid
      t.string   :landing_page
      t.string   :referrer

      t.timestamps
    end
    add_index :bookings, [ :tenant_id, :reference ], unique: true
    add_index :bookings, [ :tenant_id, :idempotency_key ], unique: true
    add_index :bookings, [ :tenant_id, :pickup_at ]
    add_index :bookings, [ :tenant_id, :status ]
    add_index :bookings, :public_token, unique: true
    add_index :bookings, :dispatch_token, unique: true

    add_foreign_key :empty_legs, :bookings, column: :source_booking_id
  end
end
