# Verifies the X-Twilio-Signature header, so only Twilio can drive our voice
# webhooks. Algorithm (Twilio docs, "Webhooks security"):
#   base64(HMAC-SHA1(auth_token, full_url + concat(sorted POST params as key+value)))
module TwilioSignature
  module_function

  def valid?(url:, params:, signature:, auth_token: Rails.configuration.x.twilio.auth_token)
    return false if auth_token.blank? || signature.blank?

    expected = compute(url: url, params: params, auth_token: auth_token)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def compute(url:, params:, auth_token:)
    data = url + params.to_h.sort.map { |key, value| "#{key}#{value}" }.join
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", auth_token, data))
  end
end
