# Routes requests for a firm's own domain (e.g. book.taxi-vaduz.li) to that
# firm's public booking site. The platform's own host never matches.
module CustomDomainConstraint
  module_function

  def matches?(request)
    host = request.host.to_s.downcase
    return false if host == Rails.configuration.x.platform.host.split(":").first

    # Every request is tested against this constraint, so cache the answer.
    Rails.cache.fetch("custom_domain:#{host}", expires_in: 1.minute) do
      Tenant.active.exists?(custom_domain: host)
    end
  end
end
