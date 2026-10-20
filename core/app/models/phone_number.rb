# Normalises phone numbers from the Liechtenstein / Swiss / Austrian region to
# E.164 (+4231234567). Deliberately small: we only need numbers good enough to
# send an SMS and to recognise a returning customer.
#
#   PhoneNumber.normalize("079 123 45 67")   # => "+41791234567"  (Swiss)
#   PhoneNumber.normalize("232 12 34")       # => "+4232321234"   (Liechtenstein)
#   PhoneNumber.normalize("0043 664 1234567")# => "+436641234567"
#
# Ambiguous national formats are resolved in favour of Switzerland, because
# Swiss numbers are by far the most common non-local numbers in the Rhine
# valley. The booking form asks foreign customers for the +country prefix.
module PhoneNumber
  E164 = /\A\+[1-9]\d{6,14}\z/

  module_function

  def normalize(raw, default_country_code: "423")
    return nil if raw.blank?

    digits = raw.to_s.strip
    plus = digits.start_with?("+")
    digits = digits.gsub(/\D/, "")
    return nil if digits.empty?

    number =
      if plus
        "+#{digits}"
      elsif digits.start_with?("00")
        "+#{digits.delete_prefix("00")}"
      elsif digits.length == 7 && default_country_code == "423"
        "+423#{digits}"                       # Liechtenstein has no trunk prefix
      elsif digits.start_with?("0") && digits.length == 10
        "+41#{digits.delete_prefix("0")}"     # Swiss national format
      elsif digits.start_with?("0")
        "+43#{digits.delete_prefix("0")}"     # Austrian national format
      else
        "+#{default_country_code}#{digits}"
      end

    number.match?(E164) ? number : nil
  end

  def valid?(raw)
    normalize(raw).present?
  end

  DISPLAY_GROUPS = { "423" => [ 3, 2, 2 ], "41" => [ 2, 3, 2, 2 ] }.freeze

  # "+41791234567" -> "+41 79 123 45 67". Display only, never stored.
  def display(e164)
    return "" if e164.blank?

    country = e164[/\A\+(423|41|43|49)/, 1]
    return e164 unless country

    rest = e164.delete_prefix("+#{country}")
    groups = DISPLAY_GROUPS[country]
    parts =
      if groups && rest.length == groups.sum
        offset = 0
        groups.map { |size| rest[offset, size].tap { offset += size } }
      else
        rest.scan(/.{1,3}/)
      end
    "+#{country} #{parts.join(" ")}"
  end
end
