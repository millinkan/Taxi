# Staff accounts. Platform admins have no tenant; everyone else belongs to
# exactly one firm.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :tenant, foreign_key: true
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :phone
      t.string :role, null: false, default: "dispatcher"
      t.string :locale, null: false, default: "de"
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :users, :email_address, unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
  end
end
