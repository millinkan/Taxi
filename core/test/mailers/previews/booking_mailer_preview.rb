# Preview the customer emails at http://localhost:3000/rails/mailers/booking_mailer
# Uses the newest booking whose customer gave an email address.
class BookingMailerPreview < ActionMailer::Preview
  Notifier::EMAIL_KEYS.each do |key|
    define_method(key) { preview(key) }
  end

  private
    def preview(key)
      booking = Booking.joins(:customer).where.not(customers: { email: [ nil, "" ] }).order(:id).last || Booking.last
      subject, body = Notifier.new(booking).compose_email(key)
      log = MessageLog.new(tenant: booking.tenant, booking: booking, channel: "email", purpose: "customer_#{key}",
                           to: booking.customer.email.presence || "customer@example.com", subject: subject, body: body)
      BookingMailer.customer_message(log)
    end
end
