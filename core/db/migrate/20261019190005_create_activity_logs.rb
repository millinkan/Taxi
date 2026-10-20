# Audit and evidence tables. These are what let us prove to a firm that the
# platform produced revenue: every call, message and status change is kept.
class CreateActivityLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.string :action, null: false
      t.string :from_status
      t.string :to_status
      t.string :actor_type, null: false, default: "system"
      t.bigint :actor_id
      t.json   :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end

    create_table :call_logs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.references :customer, foreign_key: true
      t.string   :call_sid, null: false
      t.string   :from_number
      t.string   :to_number
      t.string   :handled_by, null: false, default: "ai"
      t.string   :outcome, null: false, default: "in_progress"
      t.string   :language
      t.datetime :started_at
      t.datetime :ended_at
      t.integer  :duration_s
      t.json     :transcript, null: false, default: []
      t.text     :summary
      t.string   :recording_url

      t.timestamps
    end
    add_index :call_logs, :call_sid, unique: true
    add_index :call_logs, [ :tenant_id, :created_at ]

    create_table :message_logs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.string :channel, null: false, default: "sms"
      t.string :purpose, null: false
      t.string :to, null: false
      t.text   :body, null: false
      t.string :status, null: false, default: "queued"
      t.string :provider_id
      t.text   :error

      t.timestamps
    end
    add_index :message_logs, [ :tenant_id, :created_at ]
  end
end
