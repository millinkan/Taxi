# Language for staff pages shown before sign-in (login, password reset).
# Remembered in its own cookie, separate from the public site's :lang cookie,
# so a dispatcher's choice never changes what customers see and vice versa.
module StaffLocale
  COOKIE = :staff_lang

  private
    def set_signed_out_locale
      requested = params[:lang].presence_in(Tenant::LOCALES)
      remember_staff_locale(requested) if requested
      I18n.locale = requested || cookies[COOKIE].presence_in(Tenant::LOCALES) || I18n.default_locale
    end

    def remember_staff_locale(locale)
      cookies[COOKIE] = { value: locale, expires: 1.year, httponly: true, same_site: :lax }
    end
end
