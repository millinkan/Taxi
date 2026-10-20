# "Taxi now" requests (no lead time, the dispatcher answers with an ETA) and
# discovery by search engines and AI assistants (feeds + push log).
class AddTaxiNowAndDiscovery < ActiveRecord::Migration[8.1]
  def change
    change_table :tenants, bulk: true do |t|
      t.boolean :asap_enabled, null: false, default: true
      t.integer :asap_response_minutes, null: false, default: 3
      t.string  :opening_hours, null: false, default: "Mo-Su 00:00-23:59"
      t.string  :google_business_url
    end

    change_table :bookings, bulk: true do |t|
      t.boolean :asap, null: false, default: false
      t.integer :eta_minutes
    end

    create_table :discovery_pushes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string  :channel, null: false
      t.string  :status, null: false, default: "pending"
      t.integer :urls_count, null: false, default: 0
      t.string  :detail
      t.references :user, foreign_key: true
      t.timestamps
    end
    add_index :discovery_pushes, %i[tenant_id created_at]
  end
end
