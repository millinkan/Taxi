class ApplicationMailer < ActionMailer::Base
  default from: -> { "#{Rails.configuration.x.platform.name} <#{Rails.configuration.x.email.from}>" }
  layout "mailer"
end
