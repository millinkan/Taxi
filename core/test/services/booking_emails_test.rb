require "test_helper"

class BookingEmailsTest < ActiveSupport::TestCase
  setup do
    @tenant = create_tenant(email: "info@taxi.example", website_url: "https://www.taxi.example")
    ActionMailer::Base.deliveries.clear
  end

  test "a customer with an email address gets the booking in writing, in their language" do
    booking = create_booking(@tenant, email: "anna@example.com")
    log = messages_for(booking, "customer_received").find_by!(channel: "email")

    assert_equal "anna@example.com", log.to
    assert_equal "#{@tenant.name}: Buchungsanfrage #{booking.reference} eingegangen", log.subject
    assert_includes log.body, "Guten Tag Anna Muster,"
    assert_includes log.body, "Flughafen Zürich"
    assert_includes log.body, "CHF 290"
    assert_includes log.body, "/b/#{booking.public_token}"
    assert_no_match(/translation missing/i, log.body)
    assert_equal 1, messages_for(booking, "customer_received").where(channel: "sms").count

    perform_enqueued_jobs(only: DeliverMessageJob)
    mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "anna@example.com" ] }
    assert_equal "sent", log.reload.status
    assert_equal log.subject, mail.subject
    assert_equal [ "info@taxi.example" ], mail.reply_to
    assert_equal @tenant.name, mail[:from].display_names.first
    assert_includes mail.text_part.body.to_s, "/b/#{booking.public_token}"
    assert_match(%r{<a [^>]*href="http://[^"]+/b/#{booking.public_token}"}, mail.html_part.body.to_s)
  end

  test "confirmation, decline and the customer's own cancellation are emailed too" do
    booking = create_booking(@tenant, email: "anna@example.com", locale: "en")
    Bookings::Lifecycle.new(booking).confirm!(actor: Actor.system)
    assert_equal "#{@tenant.name}: your ride #{booking.reference} is confirmed",
                 messages_for(booking, "customer_confirmed").find_by!(channel: "email").subject

    Bookings::Lifecycle.new(booking).cancel!(actor: Actor.customer(booking.customer))
    receipt = messages_for(booking, "customer_cancelled")
    assert_equal [ "email" ], receipt.pluck(:channel), "own cancellation: email receipt only, no SMS"
    assert_includes receipt.first.body, "Book a new ride:"

    declined = create_booking(@tenant, email: "anna@example.com", pickup_at: local_time(@tenant, days: 3))
    Bookings::Lifecycle.new(declined).decline!(actor: Actor.system)
    assert messages_for(declined, "customer_declined").exists?(channel: "email")
  end

  test "no email without an address, for taxi-now requests, or when email is switched off" do
    without = create_booking(@tenant)
    assert_not without.message_logs.exists?(channel: "email")

    asap = create_booking(@tenant, email: "anna@example.com", asap: true, pickup_at: Time.current,
                                   pickup_address: "Städtle 1, Vaduz", pickup_lat: 47.141, pickup_lng: 9.521)
    assert_not asap.message_logs.exists?(channel: "email")

    Rails.configuration.x.email.enabled = false
    off = create_booking(@tenant, email: "anna@example.com", pickup_at: local_time(@tenant, days: 4))
    assert_not off.message_logs.exists?(channel: "email")
  ensure
    Rails.configuration.x.email.enabled = true
  end

  test "an SMTP failure becomes a retryable delivery error" do
    booking = create_booking(@tenant, email: "anna@example.com")
    log = messages_for(booking, "customer_received").find_by!(channel: "email")

    ActionMailer::Base.delivery_method = :busy_smtp
    error = assert_raises(Messaging::DeliveryError) { Messaging.adapter_for(log).deliver(log) }
    assert_match(/421/, error.message)
  ensure
    ActionMailer::Base.delivery_method = :test
  end

  class BusySmtp
    def initialize(_settings) = nil
    def deliver!(_mail) = raise(Net::SMTPServerBusy, "421 try again later")
  end
  ActionMailer::Base.add_delivery_method :busy_smtp, BusySmtp
end
