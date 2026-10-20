module ApplicationCable
  # Staff connect with their login session. Drivers (one-tap SMS link) and
  # customers (status page) have no login: they connect anonymously and each
  # channel checks the secret token for the one ride they may see.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = Session.find_by(id: cookies.signed[:session_id])&.user
    end
  end
end
