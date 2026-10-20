# The staff app's language (DE/EN). Stored on the user, so it follows them
# across devices and is independent of the firm's default language (used for
# customers, SMS and the phone agent) and of the public site's ?lang= choice.
class LocalesController < StaffController
  include StaffLocale

  def update
    locale = params[:lang].presence_in(Tenant::LOCALES)
    return head :unprocessable_entity unless locale

    current_user.update!(locale: locale)
    remember_staff_locale(locale)
    redirect_back_or_to root_path, status: :see_other
  end
end
