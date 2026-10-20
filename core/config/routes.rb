Rails.application.routes.draw do
  # The public booking site, mounted twice: on a firm's own domain
  # (taxi-vaduz.li/) and under the platform host (app.example.com/taxi-vaduz/).
  public_site = lambda do
    get  "/",                to: "public/bookings#new",    as: :booking_page
    post "quote",            to: "public/quotes#create",   as: :quote
    post "bookings",         to: "public/bookings#create", as: :bookings
    get  "b/:token",         to: "public/bookings#show",   as: :booking_status
    post "b/:token/cancel",  to: "public/bookings#cancel", as: :booking_cancel
    get  "deals",            to: "public/empty_legs#index", as: :deals
    get  "privacy",          to: "public/pages#privacy",   as: :privacy
    get  "now",              to: "public/now#show",        as: :now
    get  "routes/:route",    to: "public/routes#show",     as: :route
    get  "taxi/:place",      to: "public/localities#show", as: :locality

    # Discovery: what search engines and AI assistants read.
    get  "sitemap.xml",      to: "public/discovery#sitemap", as: :sitemap, format: false
    get  "llms.txt",         to: "public/discovery#llms",    as: :llms, format: false
    get  "discovery.json",   to: "public/discovery#feed",    as: :discovery_feed, format: false
  end

  constraints(CustomDomainConstraint) do
    scope as: :domain, &public_site
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "robots.txt" => "discovery#robots", format: false
  get "indexnow-key.txt" => "discovery#indexnow_key", format: false

  # --- Staff -----------------------------------------------------------------
  resource :session
  resources :passwords, param: :token
  resource :locale, only: :update
  root "home#show"

  namespace :dispatch do
    root "board#show"
    get "live" => "live#show", as: :live
    resources :bookings, only: %i[show new create update] do
      member do
        post :confirm
        post :decline
        post :start
        post :complete
        post :no_show
        post :cancel
      end
    end
    resources :calls, only: %i[index show]
    resources :empty_legs, only: %i[index destroy]
  end

  get "dashboard" => "dashboard#show", as: :dashboard
  get "exports/google-ads-conversions" => "exports#google_ads_conversions", as: :google_ads_export

  namespace :settings do
    root to: redirect("/settings/firm/edit")
    resource :firm, only: %i[edit update]
    resource :pricing, only: %i[edit update]
    resources :places, except: :show
    resources :fixed_routes, except: :show
    resources :vehicles, except: :show
  end

  namespace :admin do
    resources :tenants, except: :destroy do
      post :act_as, on: :member
      resource :discovery, only: %i[show create], controller: "discovery" do
        post :sync_places
      end
    end
    delete "act_as" => "tenants#stop_acting", as: :stop_acting
  end

  # One-tap dispatcher links sent by SMS. The secret token is the credential,
  # so the driver-dispatcher can act from the car without logging in.
  scope "d/:token", controller: :dispatch_links, as: :dispatch_link do
    get  "/",        action: :show
    post "confirm",  action: :confirm,  as: :confirm
    post "decline",  action: :decline,  as: :decline
    post "start",    action: :start,    as: :start
    post "complete", action: :complete, as: :complete
  end

  # --- Machine-to-machine ----------------------------------------------------
  namespace :internal do
    namespace :v1 do
      get  "voice/tenant", to: "voice#lookup"
      post "quotes",       to: "quotes#create"
      post "bookings",     to: "bookings#create"
      post "call_logs",    to: "call_logs#upsert"
    end
  end

  # Twilio safety net: used when the voice service is down or the AI hands off.
  namespace :twilio do
    post "voice/fallback",    to: "voice#fallback"
    post "voice/dial_status", to: "voice#dial_status"
    post "voice/voicemail",   to: "voice#voicemail"
  end

  # Must stay last: a firm slug is a catch-all first path segment.
  scope ":tenant_slug", constraints: { tenant_slug: /[a-z0-9]+(?:-[a-z0-9]+)*/ }, as: :firm, &public_site
end
