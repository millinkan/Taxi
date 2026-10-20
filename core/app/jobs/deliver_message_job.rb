class DeliverMessageJob < ApplicationJob
  queue_as :messages

  retry_on Messaging::DeliveryError, wait: :polynomially_longer, attempts: 5 do |job, error|
    MessageLog.find_by(id: job.arguments.first)&.update!(status: "failed", error: error.message)
  end

  def perform(message_log_id)
    log = MessageLog.find_by(id: message_log_id)
    return unless log && log.status == "queued"

    provider_id = Messaging.adapter_for(log).deliver(log)
    log.update!(status: "sent", provider_id: provider_id, error: nil)
  end
end
