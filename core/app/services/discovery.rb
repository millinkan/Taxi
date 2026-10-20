# Making firms findable by search engines and AI assistants. See
# Discovery::Profile (what we publish) and Discovery::Pusher (who we tell).
module Discovery
  module_function

  # IndexNow proves site ownership with a key served from the site itself.
  # Derived from the app secret unless pinned, so it is stable per deployment.
  def indexnow_key
    Rails.configuration.x.discovery.indexnow_key.presence ||
      OpenSSL::Digest::SHA256.hexdigest("indexnow:#{Rails.application.secret_key_base}")[0, 32]
  end

  # Service-account JSON for the Google Search Console API: the JSON itself
  # or a path to the file. nil when not configured.
  def google_credentials
    raw = Rails.configuration.x.discovery.google_service_account.presence
    return nil unless raw

    JSON.parse(raw.lstrip.start_with?("{") ? raw : File.read(raw))
  end
end
