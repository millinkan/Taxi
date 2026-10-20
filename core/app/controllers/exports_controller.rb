require "csv"

# Closes the loop with Google Ads: upload this file as "offline conversions"
# (Google Ads > Goals > Conversions > Uploads) and Smart Bidding starts
# optimising for completed, paid rides instead of clicks.
class ExportsController < StaffController
  before_action :require_tenant!
  before_action :require_owner!

  def google_ads_conversions
    conversion_name = params[:conversion_name].presence || "Taxi ride completed"
    since = (params[:days].presence || 90).to_i.clamp(1, 90).days.ago
    bookings = current_tenant.bookings.completed.where.not(gclid: nil).where(completed_at: since..)

    csv = CSV.generate do |rows|
      rows << [ "Parameters:TimeZone=#{current_tenant.time_zone}" ]
      rows << [ "Google Click ID", "Conversion Name", "Conversion Time", "Conversion Value", "Conversion Currency" ]
      bookings.find_each do |booking|
        rows << [
          booking.gclid, conversion_name,
          booking.completed_at.in_time_zone(current_tenant.time_zone).strftime("%Y-%m-%d %H:%M:%S"),
          format("%.2f", booking.revenue_cents / 100.0), current_tenant.currency
        ]
      end
    end

    send_data csv, type: "text/csv", filename: "google-ads-conversions-#{Date.current.iso8601}.csv"
  end
end
