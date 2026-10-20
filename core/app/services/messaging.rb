# Outbound SMS and email. Every message is first written to message_logs (the
# outbox), then delivered by a background job with retries. The log is the
# evidence trail shown on each booking and in the dashboard.
require "net/smtp"

module Messaging
  module_function

  def deliver(tenant:, to:, body:, purpose:, booking: nil, channel: "sms", subject: nil)
    if to.blank?
      return tenant.message_logs.create!(booking: booking, channel: channel, purpose: purpose, subject: subject,
                                         to: "-", body: body, status: "skipped", error: "no recipient")
    end

    log = tenant.message_logs.create!(booking: booking, channel: channel, purpose: purpose, subject: subject,
                                      to: to, body: body)
    DeliverMessageJob.perform_later(log.id)
    log
  end

  def email_enabled? = Rails.configuration.x.email.enabled

  def adapter_for(log)
    log.email? ? EmailAdapter.new : adapter
  end

  def adapter
    case Rails.configuration.x.sms_provider
    when "twilio" then TwilioAdapter.new
    when "test"   then TestAdapter
    else LogAdapter.new
    end
  end

  class DeliveryError < StandardError; end

  class TwilioAdapter
    def deliver(log)
      cfg = Rails.configuration.x.twilio
      raise DeliveryError, "Twilio credentials missing" unless cfg.account_sid && cfg.auth_token

      form = { "To" => log.to, "Body" => log.body }
      if (sender = log.tenant.sms_sender_id.presence || cfg.sms_from)
        form["From"] = sender
      elsif cfg.messaging_service_sid
        form["MessagingServiceSid"] = cfg.messaging_service_sid
      else
        raise DeliveryError, "no SMS sender configured"
      end

      url = "https://api.twilio.com/2010-04-01/Accounts/#{cfg.account_sid}/Messages.json"
      response = HttpJson.post_form(url, form: form, basic_auth: [ cfg.account_sid, cfg.auth_token ])
      response["sid"]
    rescue HttpJson::Error => e
      raise DeliveryError, e.message
    end
  end

  # Through Action Mailer: SMTP in production, a file plus the browser preview
  # in development, ActionMailer::Base.deliveries in tests.
  class EmailAdapter
    NETWORK_ERRORS = [ Net::SMTPError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

    def deliver(log)
      BookingMailer.customer_message(log).deliver_now.message_id
    rescue *NETWORK_ERRORS => e
      raise DeliveryError, "#{e.class}: #{e.message}"
    end
  end

  # Development: print to the log instead of sending.
  class LogAdapter
    def deliver(log)
      Rails.logger.info("[sms] to=#{log.to} purpose=#{log.purpose}\n#{log.body}")
      "log-#{log.id}"
    end
  end

  # Tests: collect deliveries in memory.
  module TestAdapter
    mattr_accessor :deliveries, default: []

    def self.deliver(log)
      deliveries << log
      "test-#{log.id}"
    end
  end
end
