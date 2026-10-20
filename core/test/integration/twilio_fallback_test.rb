require "test_helper"

class TwilioFallbackTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = create_tenant(voice_number: "+41445550000")
  end

  def twilio_post(path, params)
    url = "http://www.example.com#{path}"
    signature = TwilioSignature.compute(url: url, params: params, auth_token: ENV.fetch("TWILIO_AUTH_TOKEN"))
    post path, params: params, headers: { "X-Twilio-Signature" => signature }
  end

  test "rejects unsigned requests" do
    post "/twilio/voice/fallback", params: { To: "+41445550000", From: "+41795550000", CallSid: "CA1" }
    assert_response :forbidden
  end

  test "forwards the call to the dispatcher, then falls back to voicemail" do
    twilio_post "/twilio/voice/fallback", { "To" => "+41445550000", "From" => "+41795550000", "CallSid" => "CA2" }
    assert_response :success
    assert_includes response.body, "<Number>+41791234567</Number>"

    twilio_post "/twilio/voice/dial_status", { "To" => "+41445550000", "From" => "+41795550000",
                                               "CallSid" => "CA2", "DialCallStatus" => "no-answer" }
    assert_includes response.body, "<Record"

    twilio_post "/twilio/voice/voicemail", { "To" => "+41445550000", "From" => "+41795550000", "CallSid" => "CA2",
                                             "RecordingUrl" => "https://api.twilio.com/rec/RE1" }
    call = @tenant.call_logs.find_by!(call_sid: "CA2")
    assert_equal "voicemail", call.outcome
    assert_equal 1, @tenant.message_logs.where(purpose: "voicemail").count
    assert_equal 1, @tenant.message_logs.where(purpose: "missed_call_textback").count
  end
end
