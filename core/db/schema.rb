# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_19_190008) do
  create_table "booking_events", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "booking_id", null: false
    t.string "action", null: false
    t.string "from_status"
    t.string "to_status"
    t.string "actor_type", default: "system", null: false
    t.bigint "actor_id"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["booking_id"], name: "index_booking_events_on_booking_id"
    t.index ["tenant_id"], name: "index_booking_events_on_tenant_id"
  end

  create_table "bookings", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "customer_id", null: false
    t.string "reference", null: false
    t.string "idempotency_key"
    t.string "status", default: "pending", null: false
    t.string "source", default: "web", null: false
    t.string "locale", default: "de", null: false
    t.datetime "pickup_at", null: false
    t.string "pickup_address", null: false
    t.decimal "pickup_lat", precision: 10, scale: 6
    t.decimal "pickup_lng", precision: 10, scale: 6
    t.integer "pickup_place_id"
    t.string "dropoff_address", null: false
    t.decimal "dropoff_lat", precision: 10, scale: 6
    t.decimal "dropoff_lng", precision: 10, scale: 6
    t.integer "dropoff_place_id"
    t.integer "passengers", default: 1, null: false
    t.integer "luggage", default: 0, null: false
    t.string "vehicle_category", default: "standard", null: false
    t.string "flight_number"
    t.text "notes"
    t.text "internal_notes"
    t.integer "quoted_price_cents"
    t.integer "final_price_cents"
    t.string "price_source"
    t.boolean "price_estimated", default: false, null: false
    t.integer "distance_m"
    t.integer "duration_s"
    t.string "payment_method", default: "in_car", null: false
    t.integer "driver_id"
    t.integer "vehicle_id"
    t.datetime "confirmed_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.string "cancellation_reason"
    t.datetime "dispatcher_notified_at"
    t.datetime "escalated_at"
    t.datetime "review_requested_at"
    t.string "public_token", null: false
    t.string "dispatch_token", null: false
    t.integer "outbound_booking_id"
    t.integer "empty_leg_id"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.string "gclid"
    t.string "landing_page"
    t.string "referrer"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "asap", default: false, null: false
    t.integer "eta_minutes"
    t.decimal "driver_lat", precision: 10, scale: 6
    t.decimal "driver_lng", precision: 10, scale: 6
    t.integer "driver_heading"
    t.datetime "driver_located_at"
    t.index ["customer_id"], name: "index_bookings_on_customer_id"
    t.index ["dispatch_token"], name: "index_bookings_on_dispatch_token", unique: true
    t.index ["driver_id"], name: "index_bookings_on_driver_id"
    t.index ["dropoff_place_id"], name: "index_bookings_on_dropoff_place_id"
    t.index ["empty_leg_id"], name: "index_bookings_on_empty_leg_id"
    t.index ["outbound_booking_id"], name: "index_bookings_on_outbound_booking_id"
    t.index ["pickup_place_id"], name: "index_bookings_on_pickup_place_id"
    t.index ["public_token"], name: "index_bookings_on_public_token", unique: true
    t.index ["tenant_id", "idempotency_key"], name: "index_bookings_on_tenant_id_and_idempotency_key", unique: true
    t.index ["tenant_id", "pickup_at"], name: "index_bookings_on_tenant_id_and_pickup_at"
    t.index ["tenant_id", "reference"], name: "index_bookings_on_tenant_id_and_reference", unique: true
    t.index ["tenant_id", "status"], name: "index_bookings_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_bookings_on_tenant_id"
    t.index ["vehicle_id"], name: "index_bookings_on_vehicle_id"
  end

  create_table "call_logs", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "booking_id"
    t.integer "customer_id"
    t.string "call_sid", null: false
    t.string "from_number"
    t.string "to_number"
    t.string "handled_by", default: "ai", null: false
    t.string "outcome", default: "in_progress", null: false
    t.string "language"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.integer "duration_s"
    t.json "transcript", default: [], null: false
    t.text "summary"
    t.string "recording_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_call_logs_on_booking_id"
    t.index ["call_sid"], name: "index_call_logs_on_call_sid", unique: true
    t.index ["customer_id"], name: "index_call_logs_on_customer_id"
    t.index ["tenant_id", "created_at"], name: "index_call_logs_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_call_logs_on_tenant_id"
  end

  create_table "customers", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "name"
    t.string "phone", null: false
    t.string "email"
    t.string "locale", default: "de", null: false
    t.text "notes"
    t.integer "bookings_count", default: 0, null: false
    t.datetime "last_booked_at"
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "phone"], name: "index_customers_on_tenant_id_and_phone", unique: true
    t.index ["tenant_id"], name: "index_customers_on_tenant_id"
  end

  create_table "discovery_pushes", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "channel", null: false
    t.string "status", default: "pending", null: false
    t.integer "urls_count", default: 0, null: false
    t.string "detail"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "created_at"], name: "index_discovery_pushes_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_discovery_pushes_on_tenant_id"
    t.index ["user_id"], name: "index_discovery_pushes_on_user_id"
  end

  create_table "empty_legs", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "source_booking_id"
    t.string "origin_label", null: false
    t.decimal "origin_lat", precision: 10, scale: 6, null: false
    t.decimal "origin_lng", precision: 10, scale: 6, null: false
    t.string "destination_label", null: false
    t.decimal "destination_lat", precision: 10, scale: 6, null: false
    t.decimal "destination_lng", precision: 10, scale: 6, null: false
    t.datetime "available_from", null: false
    t.datetime "available_until", null: false
    t.integer "price_cents", null: false
    t.integer "regular_price_cents"
    t.string "vehicle_category", default: "standard", null: false
    t.integer "seats", default: 4, null: false
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_booking_id"], name: "index_empty_legs_on_source_booking_id"
    t.index ["tenant_id", "status", "available_from"], name: "index_empty_legs_on_tenant_id_and_status_and_available_from"
    t.index ["tenant_id"], name: "index_empty_legs_on_tenant_id"
  end

  create_table "fixed_routes", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "origin_place_id", null: false
    t.integer "destination_place_id", null: false
    t.string "vehicle_category", default: "standard", null: false
    t.integer "price_cents", null: false
    t.boolean "bidirectional", default: true, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_place_id"], name: "index_fixed_routes_on_destination_place_id"
    t.index ["origin_place_id"], name: "index_fixed_routes_on_origin_place_id"
    t.index ["tenant_id"], name: "index_fixed_routes_on_tenant_id"
  end

  create_table "message_logs", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "booking_id"
    t.string "channel", default: "sms", null: false
    t.string "purpose", null: false
    t.string "to", null: false
    t.text "body", null: false
    t.string "status", default: "queued", null: false
    t.string "provider_id"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "subject"
    t.index ["booking_id"], name: "index_message_logs_on_booking_id"
    t.index ["tenant_id", "created_at"], name: "index_message_logs_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_message_logs_on_tenant_id"
  end

  create_table "places", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "name", null: false
    t.string "kind", default: "other", null: false
    t.string "address"
    t.decimal "lat", precision: 10, scale: 6, null: false
    t.decimal "lng", precision: 10, scale: 6, null: false
    t.integer "radius_m", default: 1500, null: false
    t.text "aliases"
    t.boolean "featured", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_places_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_places_on_tenant_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tariffs", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "vehicle_category", default: "standard", null: false
    t.integer "base_fare_cents", default: 0, null: false
    t.integer "per_km_cents", default: 0, null: false
    t.integer "per_minute_cents", default: 0, null: false
    t.integer "minimum_fare_cents", default: 0, null: false
    t.integer "night_surcharge_percent", default: 0, null: false
    t.string "night_starts_at", default: "22:00", null: false
    t.string "night_ends_at", default: "06:00", null: false
    t.integer "rounding_cents", default: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "vehicle_category"], name: "index_tariffs_on_tenant_id_and_vehicle_category", unique: true
    t.index ["tenant_id"], name: "index_tariffs_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "legal_name"
    t.string "licence_number"
    t.string "status", default: "active", null: false
    t.string "time_zone", default: "Europe/Vaduz", null: false
    t.string "currency", default: "CHF", null: false
    t.string "default_locale", default: "de", null: false
    t.string "brand_color", default: "#0f766e", null: false
    t.string "logo_url"
    t.string "public_phone"
    t.string "email"
    t.string "website_url"
    t.string "google_review_url"
    t.string "custom_domain"
    t.string "dispatcher_name"
    t.string "dispatcher_phone"
    t.string "sms_sender_id"
    t.string "voice_number"
    t.boolean "voice_agent_enabled", default: false, null: false
    t.text "voice_greeting"
    t.decimal "service_center_lat", precision: 10, scale: 6
    t.decimal "service_center_lng", precision: 10, scale: 6
    t.integer "service_radius_km", default: 25, null: false
    t.string "home_area_label", default: "Liechtenstein", null: false
    t.integer "min_lead_minutes", default: 20, null: false
    t.integer "max_advance_days", default: 180, null: false
    t.boolean "auto_confirm", default: false, null: false
    t.integer "auto_confirm_min_lead_hours", default: 6, null: false
    t.integer "dispatch_escalation_minutes", default: 10, null: false
    t.integer "free_cancellation_hours", default: 2, null: false
    t.boolean "empty_legs_enabled", default: true, null: false
    t.integer "empty_leg_discount_percent", default: 40, null: false
    t.integer "empty_leg_min_distance_km", default: 40, null: false
    t.boolean "review_requests_enabled", default: true, null: false
    t.boolean "missed_call_textback_enabled", default: true, null: false
    t.integer "data_retention_days", default: 730, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "asap_enabled", default: true, null: false
    t.integer "asap_response_minutes", default: 3, null: false
    t.string "opening_hours", default: "Mo-Su 00:00-23:59", null: false
    t.string "google_business_url"
    t.index ["custom_domain"], name: "index_tenants_on_custom_domain", unique: true
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
    t.index ["voice_number"], name: "index_tenants_on_voice_number", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "tenant_id"
    t.string "name", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "phone"
    t.string "role", default: "dispatcher", null: false
    t.string "locale", default: "de", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  create_table "vehicles", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "name", null: false
    t.string "plate"
    t.string "category", default: "standard", null: false
    t.integer "seats", default: 4, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_vehicles_on_tenant_id"
  end

  add_foreign_key "booking_events", "bookings"
  add_foreign_key "booking_events", "tenants"
  add_foreign_key "bookings", "bookings", column: "outbound_booking_id"
  add_foreign_key "bookings", "customers"
  add_foreign_key "bookings", "empty_legs"
  add_foreign_key "bookings", "places", column: "dropoff_place_id"
  add_foreign_key "bookings", "places", column: "pickup_place_id"
  add_foreign_key "bookings", "tenants"
  add_foreign_key "bookings", "users", column: "driver_id"
  add_foreign_key "bookings", "vehicles"
  add_foreign_key "call_logs", "bookings"
  add_foreign_key "call_logs", "customers"
  add_foreign_key "call_logs", "tenants"
  add_foreign_key "customers", "tenants"
  add_foreign_key "discovery_pushes", "tenants"
  add_foreign_key "discovery_pushes", "users"
  add_foreign_key "empty_legs", "bookings", column: "source_booking_id"
  add_foreign_key "empty_legs", "tenants"
  add_foreign_key "fixed_routes", "places", column: "destination_place_id"
  add_foreign_key "fixed_routes", "places", column: "origin_place_id"
  add_foreign_key "fixed_routes", "tenants"
  add_foreign_key "message_logs", "bookings"
  add_foreign_key "message_logs", "tenants"
  add_foreign_key "places", "tenants"
  add_foreign_key "sessions", "users"
  add_foreign_key "tariffs", "tenants"
  add_foreign_key "users", "tenants"
  add_foreign_key "vehicles", "tenants"
end
