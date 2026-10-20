# Sends a booking email that Notifier already wrote to the outbox, so what the
# customer receives is exactly what the booking's message log shows.
class BookingMailer < ApplicationMailer
  helper do
    # The stored text, as HTML: paragraphs, line breaks and clickable links.
    def email_paragraphs(text)
      safe_join(text.split(/\n{2,}/).map do |paragraph|
        lines = paragraph.split("\n").map do |line|
          safe_join(line.split(%r{(https?://\S+)}).map.with_index do |part, index|
            index.odd? ? link_to(part, part, style: "color: #{@tenant.brand_color};") : part
          end)
        end
        tag.p(safe_join(lines, tag.br), style: "margin: 0 0 14px;")
      end)
    end
  end

  def customer_message(log)
    @log = log
    @tenant = log.tenant
    mail to: log.to, subject: log.subject,
         from: email_address_with_name(Rails.configuration.x.email.from, @tenant.name),
         reply_to: @tenant.email.presence
  end
end
