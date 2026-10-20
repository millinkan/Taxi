# Recurring (config/recurring.yml). GDPR / Swiss nFADP storage limitation:
# after each firm's retention period we anonymise inactive customers and wipe
# call transcripts and message bodies. Booking rows and amounts stay, because
# the firm needs them for its accounts.
class DataRetentionJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.find_each do |tenant|
      cutoff = tenant.data_retention_days.days.ago

      tenant.customers.where(anonymized_at: nil)
            .where("last_booked_at < ? OR (last_booked_at IS NULL AND created_at < ?)", cutoff, cutoff)
            .find_each(&:anonymize!)

      tenant.call_logs.where(created_at: ...cutoff)
            .update_all(transcript: [], summary: nil, recording_url: nil, from_number: nil)

      tenant.message_logs.where(created_at: ...cutoff).update_all(body: "[deleted]", to: "-")
    end
  end
end
