# Live tracking: the driver's latest position while a ride is active. Only the
# latest point is kept (no history), and it is cleared when the ride ends.
class AddLiveDriverPosition < ActiveRecord::Migration[8.1]
  def change
    change_table :bookings, bulk: true do |t|
      t.decimal  :driver_lat, precision: 10, scale: 6
      t.decimal  :driver_lng, precision: 10, scale: 6
      t.integer  :driver_heading
      t.datetime :driver_located_at
    end
  end
end
