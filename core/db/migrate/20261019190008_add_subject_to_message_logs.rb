# Booking emails go through the same outbox as SMS; only emails have a subject.
class AddSubjectToMessageLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :message_logs, :subject, :string
  end
end
