# A tenant is one taxi firm. Everything a firm owns hangs off tenant_id, so
# onboarding a new firm is a row of configuration, never new code.
class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :legal_name
      t.string  :licence_number
      t.string  :status, null: false, default: "active"

      # Locale, money and time
      t.string  :time_zone, null: false, default: "Europe/Vaduz"
      t.string  :currency, null: false, default: "CHF"
      t.string  :default_locale, null: false, default: "de"

      # Brand and public contact
      t.string  :brand_color, null: false, default: "#0f766e"
      t.string  :logo_url
      t.string  :public_phone
      t.string  :email
      t.string  :website_url
      t.string  :google_review_url
      t.string  :custom_domain

      # Dispatch: who gets told about new bookings
      t.string  :dispatcher_name
      t.string  :dispatcher_phone
      t.string  :sms_sender_id

      # Voice agent
      t.string  :voice_number
      t.boolean :voice_agent_enabled, null: false, default: false
      t.text    :voice_greeting

      # Service area (a circle is enough for a firm; fixed routes handle the rest)
      t.decimal :service_center_lat, precision: 10, scale: 6
      t.decimal :service_center_lng, precision: 10, scale: 6
      t.integer :service_radius_km, null: false, default: 25
      t.string  :home_area_label, null: false, default: "Liechtenstein"

      # Booking policy
      t.integer :min_lead_minutes, null: false, default: 20
      t.integer :max_advance_days, null: false, default: 180
      t.boolean :auto_confirm, null: false, default: false
      t.integer :auto_confirm_min_lead_hours, null: false, default: 6
      t.integer :dispatch_escalation_minutes, null: false, default: 10
      t.integer :free_cancellation_hours, null: false, default: 2

      # Revenue features
      t.boolean :empty_legs_enabled, null: false, default: true
      t.integer :empty_leg_discount_percent, null: false, default: 40
      t.integer :empty_leg_min_distance_km, null: false, default: 40
      t.boolean :review_requests_enabled, null: false, default: true
      t.boolean :missed_call_textback_enabled, null: false, default: true

      # Privacy
      t.integer :data_retention_days, null: false, default: 730

      t.timestamps
    end

    add_index :tenants, :slug, unique: true
    add_index :tenants, :custom_domain, unique: true
    add_index :tenants, :voice_number, unique: true
  end
end
