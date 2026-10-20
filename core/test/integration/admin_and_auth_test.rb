require "test_helper"

class AdminAndAuthTest < ActionDispatch::IntegrationTest
  test "sign in and out" do
    tenant = create_tenant
    get "/session/new"
    assert_response :success

    post session_path, params: { email_address: owner_of(tenant).email_address, password: "wrong-password" }
    assert_redirected_to new_session_path

    sign_in owner_of(tenant)
    get "/"
    assert_redirected_to "/dispatch"

    delete session_path
    get "/dispatch"
    assert_redirected_to new_session_path
  end

  test "deactivated users are locked out" do
    tenant = create_tenant
    user = create_user(tenant: tenant)
    sign_in user
    user.update!(active: false)
    get "/dispatch"
    assert_redirected_to new_session_path
  end

  test "platform admin onboards a new firm with the regional template" do
    admin = create_platform_admin
    sign_in admin

    get "/admin/tenants/new"
    assert_response :success

    post "/admin/tenants", params: {
      region: "liechtenstein",
      tenant: { name: "Taxi Balzers", slug: "taxi-balzers", dispatcher_phone: "+41791110000", status: "active",
                default_locale: "de" },
      owner: { name: "Paul", email_address: "paul@taxi-balzers.example", password: "a-long-password" }
    }
    tenant = Tenant.find_by!(slug: "taxi-balzers")
    assert_redirected_to "/admin/tenants/#{tenant.id}"
    assert tenant.fixed_routes.any?
    assert_equal "Europe/Vaduz", tenant.time_zone

    post "/admin/tenants/#{tenant.id}/act_as"
    get "/dispatch"
    assert_response :success
    assert_select ".acting-banner"

    get "/taxi-balzers"
    assert_response :success
  end

  test "platform admin switches the staff language between German and English" do
    tenant = create_tenant
    admin = create_platform_admin
    sign_in admin

    get "/admin/tenants"
    assert_select "h1", I18n.t("admin.title", locale: :de)
    assert_select ".staff-lang button[aria-pressed=true]", "DE"

    patch locale_path, params: { lang: "en" }, headers: { "HTTP_REFERER" => "http://www.example.com/admin/tenants" }
    assert_redirected_to "/admin/tenants"
    assert_equal "en", admin.reload.locale

    follow_redirect!
    assert_select "html[lang=en]"
    assert_select "h1", I18n.t("admin.title", locale: :en)
    assert_select ".staff-lang button[aria-pressed=true]", "EN"

    # Independent of the firm: its customers still get the firm's default language.
    assert_equal "de", tenant.reload.default_locale
    get "/#{tenant.slug}"
    assert_select "html[lang=de]"

    patch locale_path, params: { lang: "de" }
    assert_equal "de", admin.reload.locale

    patch locale_path, params: { lang: "fr" }
    assert_response :unprocessable_entity
    assert_equal "de", admin.reload.locale
  end

  test "sign-in page language can be switched and is remembered" do
    get "/session/new", params: { lang: "en" }
    assert_select "html[lang=en]"
    assert_select "h1", I18n.t("auth.sign_in", locale: :en)

    get "/session/new"
    assert_select "html[lang=en]"

    get "/session/new", params: { lang: "de" }
    assert_select "h1", I18n.t("auth.sign_in", locale: :de)
  end

  test "language switch requires sign-in" do
    patch locale_path, params: { lang: "en" }
    assert_redirected_to new_session_path
  end

  test "non-admins cannot reach the admin area" do
    tenant = create_tenant
    sign_in owner_of(tenant)
    get "/admin/tenants"
    assert_response :forbidden
  end
end
