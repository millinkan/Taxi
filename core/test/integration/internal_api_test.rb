require "test_helper"

class InternalApiTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(voice_number: "+41445550000", voice_agent_enabled: true)
    @pickup_at = local_time(@tenant, days: 1, hour: 6, min: 30).strftime("%Y-%m-%dT%H:%M")
  end

  test "rejects requests without the shared token" do
    get "/internal/v1/voice/tenant", params: { number: "+41445550000" }
    assert_response :unauthorized

    get "/internal/v1/voice/tenant", params: { number: "+41445550000" },
                                      headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
  end

  test "looks up the firm by the dialled number" do
    get "/internal/v1/voice/tenant", params: { number: "+41 44 555 00 00" }, headers: internal_headers
    assert_response :success
    assert_equal @tenant.id, json.dig("tenant", "id")
    assert json.dig("tenant", "places").any? { |p| p["name"] == "Flughafen Zürich" }

    get "/internal/v1/voice/tenant", params: { number: "+41000000000" }, headers: internal_headers
    assert_response :not_found
  end

  test "quotes a trip in the firm's local time" do
    post "/internal/v1/quotes", params: {
      tenant_id: @tenant.id, pickup_address: "Schaan", dropoff_address: "Zurich Airport",
      pickup_at: @pickup_at, passengers: 2
    }, headers: internal_headers, as: :json

    assert_response :success
    assert_equal "CHF 290", json["price_text"]
    assert json["lead_time_ok"]
    assert json["capacity_available"]
    assert_equal "Flughafen Zürich", json.dig("dropoff", "label")
  end

  test "creates a voice booking once, links the call and records it" do
    params = {
      tenant_id: @tenant.id, pickup_address: "Schaan", dropoff_address: "ZRH", pickup_at: @pickup_at,
      passengers: 2, name: "Maria Beck", phone: "+41795551234", call_sid: "CA_voice_1",
      idempotency_key: "toolu_abc", locale: "de"
    }
    post "/internal/v1/bookings", params: params, headers: internal_headers, as: :json
    assert_response :created
    reference = json.dig("booking", "reference")

    post "/internal/v1/bookings", params: params, headers: internal_headers, as: :json
    assert_equal reference, json.dig("booking", "reference")
    assert_equal 1, @tenant.bookings.count

    booking = @tenant.bookings.sole
    assert_equal "voice", booking.source
    call = @tenant.call_logs.find_by!(call_sid: "CA_voice_1")
    assert_equal booking, call.booking
    assert_equal "booked", call.outcome
  end

  test "call log upsert keeps the transcript and texts back abandoned callers" do
    post "/internal/v1/call_logs", params: {
      tenant_id: @tenant.id, call_sid: "CA_hangup", from_number: "+41795550000", to_number: "+41445550000",
      outcome: "abandoned", duration_s: 12, handled_by: "ai",
      transcript: [ { role: "agent", text: "Grüezi" }, { role: "caller", text: "..." } ]
    }, headers: internal_headers, as: :json

    assert_response :success
    call = @tenant.call_logs.find_by!(call_sid: "CA_hangup")
    assert_equal 2, call.transcript.size
    assert_equal 1, @tenant.message_logs.where(purpose: "missed_call_textback").count
  end
end
