ENV["RAILS_ENV"] ||= "test"
ENV["INTERNAL_API_TOKEN"] ||= "test-internal-token"
ENV["TWILIO_AUTH_TOKEN"] ||= "test-twilio-token"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "support/factories"

module ActiveSupport
  class TestCase
    # Serial: SQLite + thread workers share one connection, and Windows cannot
    # fork process workers. The suite is fast enough either way.
    parallelize(workers: 1)

    include ActiveJob::TestHelper
    include Factories

    # Every test runs at a fixed local moment: Monday 19 Oct 2026, 10:00 in
    # Vaduz. Lead-time rules and night tariffs are then deterministic.
    setup { travel_to Time.utc(2026, 10, 19, 8, 0, 0) }
    teardown { travel_back }
  end
end

class ActionDispatch::IntegrationTest
  def json = JSON.parse(response.body)

  def internal_headers
    { "Authorization" => "Bearer #{ENV.fetch("INTERNAL_API_TOKEN")}", "Accept" => "application/json" }
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: Factories::PASSWORD }
    assert_response :redirect
  end
end
