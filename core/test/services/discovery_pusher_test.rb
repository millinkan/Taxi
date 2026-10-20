require "test_helper"

class DiscoveryPusherTest < ActiveSupport::TestCase
  # Records outbound calls instead of making them.
  class FakeHttp
    attr_reader :calls

    def initialize(fail_with: nil)
      @calls = []
      @fail_with = fail_with
    end

    def post_json(url, body:, headers: {})
      record(:post_json, url, body: body)
    end

    def post_form(url, form:, basic_auth: nil)
      record(:post_form, url, form: form).merge("access_token" => "ya29.token")
    end

    def put(url, headers: {})
      record(:put, url, headers: headers)
    end

    private
      def record(verb, url, **details)
        raise HttpJson::Error, @fail_with if @fail_with

        @calls << { verb: verb, url: url, **details }
        {}
      end
  end

  setup do
    @tenant = create_tenant(slug: "taxi-push", custom_domain: "taxi-push.li")
    @http = FakeHttp.new
    Discovery::Pusher.http = @http
  end

  teardown do
    Discovery::Pusher.http = HttpJson
    Rails.configuration.x.discovery.google_service_account = nil
  end

  def push(channel) = @tenant.discovery_pushes.create!(channel: channel)

  test "IndexNow receives every public URL with the ownership key" do
    record = push("indexnow")
    Discovery::Pusher.new(record).call

    call = @http.calls.sole
    assert_equal Discovery::Pusher::INDEXNOW_ENDPOINT, call[:url]
    assert_equal "taxi-push.li", call[:body][:host]
    assert_equal "https://taxi-push.li/indexnow-key.txt", call[:body][:keyLocation]
    assert_equal Discovery.indexnow_key, call[:body][:key]
    assert_includes call[:body][:urlList], "https://taxi-push.li/now"
    assert_equal "ok", record.reload.status
    assert_equal call[:body][:urlList].size, record.urls_count
  end

  test "local hosts are never submitted" do
    @tenant.update!(custom_domain: nil)
    record = push("indexnow")
    Discovery::Pusher.new(record).call

    assert_empty @http.calls
    assert_equal "skipped", record.reload.status
  end

  test "Google is skipped until Search Console is configured" do
    record = push("google")
    Discovery::Pusher.new(record).call

    assert_empty @http.calls
    assert_equal "skipped", record.reload.status
  end

  test "Google gets the sitemap through the Search Console API" do
    key = OpenSSL::PKey::RSA.new(2048)
    Rails.configuration.x.discovery.google_service_account =
      { client_email: "pusher@project.iam.gserviceaccount.com", private_key: key.to_pem }.to_json

    record = push("google")
    Discovery::Pusher.new(record).call

    token_call, submit = @http.calls
    assert_equal Discovery::Pusher::GOOGLE_TOKEN_URL, token_call[:url]
    header, claims, signature = token_call[:form][:assertion].split(".")
    assert_equal "pusher@project.iam.gserviceaccount.com", JSON.parse(Base64.urlsafe_decode64(claims))["iss"]
    assert key.public_key.verify("SHA256", Base64.urlsafe_decode64(signature), "#{header}.#{claims}")

    assert_equal :put, submit[:verb]
    assert_equal "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Ataxi-push.li/sitemaps/https%3A%2F%2Ftaxi-push.li%2Fsitemap.xml",
                 submit[:url]
    assert_equal "Bearer ya29.token", submit[:headers]["Authorization"]
    assert_equal "ok", record.reload.status
  end

  test "a failing engine is logged, not raised" do
    Discovery::Pusher.http = FakeHttp.new(fail_with: "HTTP 403 from api.indexnow.org: key not found")
    record = push("indexnow")
    Discovery::Pusher.new(record).call

    assert_equal "failed", record.reload.status
    assert_match(/403/, record.detail)
  end
end
