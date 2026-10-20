# Every SMS and email the platform sends, in one place. Texts live under
# "sms" and "email" in config/locales/*.yml; customers get their own language,
# dispatchers get the firm's default language.
class Notifier
  include PriceFormatting

  # Customers who gave an email address also get these steps in writing.
  # "Taxi now" texts are left out: those customers are watching their phone.
  EMAIL_KEYS = %w[received confirmed declined cancelled].freeze

  def initialize(booking)
    @booking = booking
    @tenant = booking.tenant
    @urls = TenantUrls.new(@tenant)
  end

  # --- to the dispatcher -------------------------------------------------

  def dispatcher_new_booking
    prefix = if !@booking.pending? then "auto_confirmed"
    elsif @booking.asap? then "asap"
    else "new"
    end
    to_dispatcher(:dispatcher_new_booking, prefix: prefix)
    @booking.update_column(:dispatcher_notified_at, Time.current)
  end

  def dispatcher_reminder
    to_dispatcher(:dispatcher_reminder, prefix: "reminder")
  end

  def dispatcher_cancelled_by_customer
    to_dispatcher(:dispatcher_cancelled, prefix: "cancelled")
  end

  def dispatcher_asap_missed
    to_dispatcher(:dispatcher_asap_missed, prefix: "asap_missed")
  end

  # --- to the customer ---------------------------------------------------

  def customer_received = to_customer(:customer_received, key: @booking.asap? ? "received_asap" : nil)
  def customer_confirmed = to_customer(:customer_confirmed, key: @booking.asap? ? "confirmed_asap" : nil)
  def customer_asap_unavailable = to_customer(:customer_asap_unavailable)
  def customer_declined = to_customer(:customer_declined)
  def customer_cancelled = to_customer(:customer_cancelled)
  def customer_on_the_way = to_customer(:customer_on_the_way)

  # The customer cancelled online and already sees it on screen; the email is
  # their written record.
  def customer_cancellation_receipt = email_customer(:customer_cancelled, "cancelled")

  # [subject, body] in the customer's language.
  def compose_email(key)
    I18n.with_locale(@booking.locale) do
      [ I18n.t("email.customer.#{key}.subject", **customer_vars), email_body(key) ]
    end
  end

  def customer_review_request
    return unless @tenant.review_requests_enabled? && @tenant.google_review_url.present?

    to_customer(:customer_review_request)
    @booking.update_column(:review_requested_at, Time.current)
  end

  private
    def to_dispatcher(purpose, prefix:)
      body = I18n.with_locale(@tenant.default_locale) do
        I18n.t("sms.dispatcher.#{prefix}", **dispatcher_vars)
      end
      Messaging.deliver(tenant: @tenant, booking: @booking, to: @tenant.dispatcher_phone,
                        body: body, purpose: purpose.to_s)
    end

    def to_customer(purpose, key: nil)
      key ||= purpose.to_s.delete_prefix("customer_")
      body = I18n.with_locale(@booking.locale) { I18n.t("sms.customer.#{key}", **customer_vars) }
      Messaging.deliver(tenant: @tenant, booking: @booking, to: @booking.customer.phone,
                        body: body, purpose: purpose.to_s)
      email_customer(purpose, key)
    end

    def email_customer(purpose, key)
      address = @booking.customer.email
      return unless EMAIL_KEYS.include?(key) && address.present? && Messaging.email_enabled?

      subject, body = compose_email(key)
      Messaging.deliver(tenant: @tenant, booking: @booking, to: address, subject: subject, body: body,
                        purpose: purpose.to_s, channel: "email")
    end

    def email_body(key)
      vars = customer_vars
      name = @booking.customer.name.presence
      lines = [ name ? I18n.t("email.greeting_name", name: name) : I18n.t("email.greeting"), "",
                I18n.t("email.customer.#{key}.intro", **vars), "" ]
      email_details(vars).each { |label, value| lines << "#{I18n.t("email.labels.#{label}")}: #{value}" }
      lines << ""
      if @booking.open?
        lines << I18n.t(@booking.customer_cancellable? ? "email.manage" : "email.details") << vars[:link] << ""
      else
        lines << I18n.t("email.book_again") << vars[:book_link] << ""
      end
      lines << I18n.t("email.questions", phone: vars[:phone]) << "" << "-- " << email_signature
      lines.join("\n")
    end

    def email_details(vars)
      {
        ref: @booking.reference,
        when: I18n.l(@booking.local_pickup_at, format: :long_day),
        from: @booking.pickup_address,
        to: @booking.dropoff_address,
        passengers: "#{@booking.passengers} · #{I18n.t("vehicle_categories.#{@booking.vehicle_category}")}",
        flight: @booking.flight_number,
        vehicle: (@booking.vehicle&.label if @booking.committed?),
        price: vars[:price]
      }.compact_blank
    end

    def email_signature
      [ @tenant.name, @tenant.legal_name.presence && @tenant.licence_number.presence &&
                      "#{@tenant.legal_name} · #{I18n.t("public.licence", number: @tenant.licence_number)}",
        PhoneNumber.display(@tenant.public_phone.presence || @tenant.dispatcher_phone),
        @tenant.website_url.presence ].compact_blank.join("\n")
    end

    def dispatcher_vars
      {
        when: I18n.l(@booking.local_pickup_at, format: :sms),
        from: @booking.pickup_address.truncate(40),
        to: @booking.dropoff_address.truncate(40),
        pax: @booking.passengers,
        price: price_text,
        name: @booking.customer.display_name.truncate(30),
        phone: @booking.customer.phone,
        extra: dispatcher_extra,
        link: @urls.dispatch_link(@booking),
        minutes: @tenant.asap_response_minutes
      }
    end

    def dispatcher_extra
      parts = []
      parts << I18n.t("sms.flight", number: @booking.flight_number) if @booking.flight_number.present?
      parts << I18n.t("vehicle_categories.#{@booking.vehicle_category}") unless @booking.vehicle_category == "standard"
      parts << I18n.t("sms.source.#{@booking.source}")
      parts.join(", ") # plain GSM-7 characters keep an SMS at 160 chars per segment
    end

    def customer_vars
      {
        firm: @tenant.name,
        ref: @booking.reference,
        when: I18n.l(@booking.local_pickup_at, format: :sms),
        from: @booking.pickup_address.truncate(40),
        price: price_text,
        phone: PhoneNumber.display(@tenant.public_phone.presence || @tenant.dispatcher_phone),
        link: @urls.status_page(@booking),
        review_link: @tenant.google_review_url.to_s,
        vehicle: @booking.vehicle&.label.to_s,
        eta: @booking.eta_minutes,
        minutes: @tenant.asap_response_minutes,
        book_link: @urls.booking_page
      }
    end

    def price_text
      format_price(@booking.final_price_cents || @booking.quoted_price_cents, @tenant.currency,
                   estimated: @booking.final_price_cents.nil? && @booking.price_estimated?)
    end
end
