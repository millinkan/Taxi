module ApplicationHelper
  include PriceFormatting

  def status_badge(booking_or_status)
    status = booking_or_status.respond_to?(:status) ? booking_or_status.status : booking_or_status.to_s
    tag.span(t("statuses.#{status}"), class: "badge badge--#{status}")
  end

  def money(cents, currency = Current.tenant&.currency || "CHF", estimated: false)
    format_price(cents, currency, estimated: estimated)
  end

  def booking_price(booking)
    money(booking.final_price_cents || booking.quoted_price_cents, booking.tenant.currency,
          estimated: booking.final_price_cents.nil? && booking.price_estimated?)
  end

  def pickup_time(booking, format: :short_day)
    l(booking.local_pickup_at, format: format)
  end

  def phone_link(e164, **options)
    return "" if e164.blank?

    link_to PhoneNumber.display(e164), "tel:#{e164}", **options
  end

  def source_label(source)
    t("sources.#{source}")
  end

  # Readable text colour on top of an arbitrary brand colour (WCAG luminance).
  def ink_on(hex)
    r, g, b = hex.to_s.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    return "#ffffff" unless r && g && b

    lin = ->(c) { c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    luminance = 0.2126 * lin.(r) + 0.7152 * lin.(g) + 0.0722 * lin.(b)
    luminance > 0.45 ? "#111111" : "#ffffff"
  end

  def nav_link(label, path, active: current_page?(path))
    link_to label, path, "aria-current": (active ? "page" : nil)
  end

  def form_errors(errors)
    messages = errors.respond_to?(:full_messages) ? errors.full_messages : Array(errors)
    return if messages.empty?

    tag.ul(class: "errors", role: "alert") { safe_join(messages.map { |m| tag.li(m) }) }
  end

  # Only plain https links from stored settings become hrefs; anything else
  # (javascript:, data:) is dropped even if validation was ever bypassed.
  def external_https_url(url)
    uri = URI.parse(url.to_s)
    uri.to_s if uri.is_a?(URI::HTTPS) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # schema.org description of the firm for search engines and AI assistants.
  def discovery_json_ld(tenant)
    tag.script(json_escape(Discovery::Profile.new(tenant).json_ld.to_json).html_safe, type: "application/ld+json")
  end

  def percent(ratio)
    number_to_percentage(ratio.to_f * 100, precision: 0)
  end
end
