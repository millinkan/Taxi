require "net/http"

# Minimal JSON-over-HTTP client with hard timeouts. Every outbound call in the
# booking path goes through here so a slow provider can never hang a request.
module HttpJson
  class Error < StandardError; end

  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 6

  module_function

  def get(url, params: {}, headers: {})
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params.any?
    request(uri, Net::HTTP::Get.new(uri, headers))
  end

  def post_json(url, body:, headers: {})
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json" }.merge(headers))
    req.body = body.to_json
    request(uri, req)
  end

  def put(url, headers: {})
    uri = URI(url)
    request(uri, Net::HTTP::Put.new(uri, headers))
  end

  def post_form(url, form:, basic_auth: nil)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    req.basic_auth(*basic_auth) if basic_auth
    req.set_form_data(form)
    request(uri, req)
  end

  def request(uri, req)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(req)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "HTTP #{response.code} from #{uri.host}: #{response.body.to_s.truncate(300)}"
    end

    response.body.present? ? JSON.parse(response.body) : {}
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from #{uri.host}: #{e.message}"
  rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError => e
    raise Error, "#{e.class} talking to #{uri.host}: #{e.message}"
  end
end
