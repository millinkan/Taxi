module Twilio
  # The phone safety net. Twilio calls these webhooks when:
  #   * the voice service is unreachable (configured as the number's
  #     "primary handler fails" URL) -> /twilio/voice/fallback
  #   * a forwarded call to the dispatcher ends -> /twilio/voice/dial_status
  #   * a voicemail has been recorded -> /twilio/voice/voicemail
  #
  # Chain: ring the dispatcher -> voicemail -> SMS the caller a booking link.
  # A call must never simply die.
  class VoiceController < ActionController::Base
    skip_forgery_protection
    before_action :verify_signature
    before_action :set_tenant

    DIAL_TIMEOUT_SECONDS = 25

    def fallback
      log_call(outcome: "in_progress", handled_by: "fallback")
      return render_voicemail_prompt if @tenant.dispatcher_phone.blank?

      render_twiml do |xml|
        say(xml, :connecting)
        xml << dial_xml
      end
    end

    def dial_status
      if params[:DialCallStatus] == "completed"
        log_call(outcome: "transferred")
        render_twiml { |xml| xml << "<Hangup/>" }
      else
        render_voicemail_prompt
      end
    end

    def voicemail
      call = log_call(outcome: "voicemail", recording_url: params[:RecordingUrl].presence)
      if params[:RecordingUrl].present? && @tenant.dispatcher_phone.present?
        body = I18n.with_locale(@tenant.default_locale) do
          I18n.t("sms.dispatcher.voicemail", from: params[:From].to_s, url: "#{params[:RecordingUrl]}.mp3")
        end
        Messaging.deliver(tenant: @tenant, to: @tenant.dispatcher_phone, body: body, purpose: "voicemail")
      end
      CallFollowUp.new(call).perform
      render_twiml do |xml|
        say(xml, :thanks)
        xml << "<Hangup/>"
      end
    end

    private
      def verify_signature
        base = Rails.configuration.x.twilio.webhook_base_url
        url = base ? "#{base.chomp("/")}#{request.fullpath}" : request.original_url
        signature = request.headers["X-Twilio-Signature"]
        params_for_signature = request.request_parameters

        head :forbidden unless TwilioSignature.valid?(url: url, params: params_for_signature, signature: signature)
      end

      def set_tenant
        @tenant = Tenant.active.for_voice_number(params[:To]) || Tenant.active.for_voice_number(params[:Called])
        return if @tenant

        render_twiml do |xml|
          xml << %(<Say language="de-DE">#{ERB::Util.html_escape(I18n.t("twilio.unknown_number", locale: :de))}</Say><Hangup/>)
        end
      end

      def log_call(outcome:, handled_by: nil, recording_url: nil)
        call = @tenant.call_logs.find_or_initialize_by(call_sid: params[:CallSid].presence || SecureRandom.uuid)
        call.from_number ||= params[:From]
        call.to_number ||= params[:To]
        call.started_at ||= Time.current
        call.handled_by = handled_by if handled_by
        call.outcome = outcome unless call.outcome == "booked"
        call.recording_url = recording_url if recording_url
        call.save!
        call
      end

      def render_voicemail_prompt
        render_twiml do |xml|
          say(xml, :voicemail_prompt)
          xml << %(<Record maxLength="120" playBeep="true" timeout="5" action="#{url_for(action: :voicemail)}"/>)
          say(xml, :goodbye)
        end
      end

      def dial_xml
        number = ERB::Util.html_escape(@tenant.dispatcher_phone)
        action = url_for(action: :dial_status)
        %(<Dial timeout="#{DIAL_TIMEOUT_SECONDS}" action="#{action}"><Number>#{number}</Number></Dial>)
      end

      def say(xml, key)
        voice_locale = @tenant.default_locale == "en" ? "en-GB" : "de-DE"
        text = I18n.t("twilio.#{key}", firm: @tenant.name, locale: @tenant.default_locale)
        xml << %(<Say language="#{voice_locale}">#{ERB::Util.html_escape(text)}</Say>)
      end

      def render_twiml
        xml = +%(<?xml version="1.0" encoding="UTF-8"?><Response>)
        yield xml
        xml << "</Response>"
        render plain: xml, content_type: "text/xml"
      end
  end
end
