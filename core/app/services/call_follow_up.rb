# What happens after a call that did not end in a booking: a caller who hung
# up or reached voicemail gets an SMS with the booking link ("missed-call
# text-back"), so the ride is not lost to the next taxi firm on Google.
class CallFollowUp
  TEXTBACK_OUTCOMES = %w[abandoned voicemail failed].freeze

  def initialize(call)
    @call = call
    @tenant = call.tenant
  end

  def perform
    return unless textback?

    locale = @call.customer&.locale || @tenant.default_locale
    body = I18n.with_locale(locale) do
      I18n.t("sms.customer.missed_call", firm: @tenant.name, link: TenantUrls.new(@tenant).booking_page)
    end
    Messaging.deliver(tenant: @tenant, to: caller_number, body: body, purpose: "missed_call_textback")
  end

  private
    def textback?
      @tenant.missed_call_textback_enabled? &&
        TEXTBACK_OUTCOMES.include?(@call.outcome) &&
        caller_number.present? &&
        !already_texted?
    end

    def caller_number
      @caller_number ||= PhoneNumber.normalize(@call.from_number)
    end

    # One text-back per number per day is helpful; more is spam.
    def already_texted?
      @tenant.message_logs.where(purpose: "missed_call_textback", to: caller_number, created_at: 24.hours.ago..).exists?
    end
end
