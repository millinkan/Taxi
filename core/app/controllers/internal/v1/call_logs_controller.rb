module Internal
  module V1
    # Final record of a call handled by the voice agent (sent when the call
    # ends). Upserts by Twilio CallSid so it can be sent more than once.
    class CallLogsController < BaseController
      def upsert
        call = tenant.call_logs.find_or_initialize_by(call_sid: params.require(:call_sid))
        attrs = params.permit(:from_number, :to_number, :language, :summary, :duration_s, :handled_by)
                      .to_h.compact_blank
        call.assign_attributes(attrs)
        call.started_at ||= parse_time(params[:started_at]) || Time.current
        call.ended_at = parse_time(params[:ended_at]) if params[:ended_at]
        call.transcript = sanitized_transcript if params.key?(:transcript)
        # A booking made during the call wins over whatever the agent reports.
        call.outcome = call.booking_id ? "booked" : params[:outcome].presence_in(CallLog::OUTCOMES) || call.outcome
        call.customer ||= tenant.customers.find_by(phone: PhoneNumber.normalize(call.from_number)) if call.from_number
        call.save!

        CallFollowUp.new(call).perform
        render json: { ok: true, id: call.id, outcome: call.outcome }
      end

      private
        def parse_time(value)
          Time.zone.parse(value.to_s) if value.present?
        rescue ArgumentError
          nil
        end

        def sanitized_transcript
          Array(params[:transcript]).first(400).filter_map do |turn|
            next unless turn.respond_to?(:permit)

            entry = turn.permit(:role, :text).to_h
            { "role" => entry["role"].to_s.presence_in(%w[caller agent]) || "agent",
              "text" => entry["text"].to_s.truncate(2000) }
          end
        end
    end
  end
end
