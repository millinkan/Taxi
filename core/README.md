# RideDesk core (Rails)

Firms, prices, bookings, customers, SMS, dashboards and the Twilio safety net.
Project overview and all documentation: [../README.md](../README.md) and [../docs](../docs).

```powershell
bundle install
ruby bin/rails db:prepare      # create + migrate + seed a demo firm (dev only)
ruby bin/rails server          # http://localhost:3000  (demo: /taxi-demo)
ruby bin/rails test            # full test suite
ruby bin/brakeman; ruby bin/rubocop
```

## Where things are

| Path | What |
|---|---|
| `app/models/` | Domain models (`Tenant`, `Booking`, `Place`, `FixedRoute`, …) and value objects (`PhoneNumber`, `Geo`, `Actor`) |
| `app/services/` | Business logic: `Pricing`, `Bookings::{Request,Creator,Lifecycle}`, `DispatchCapacity`, `EmptyLegs::Publisher`, `Notifier`, `Messaging`, `Geocoding`, `Routing`, `TenantOnboarding`, `PerformanceReport` |
| `app/controllers/public/` | Customer booking site (per firm, by slug or custom domain) |
| `app/controllers/dispatch/`, `dispatch_links_controller.rb` | Dispatcher board and one-tap SMS links |
| `app/controllers/settings/`, `dashboard_controller.rb`, `exports_controller.rb` | Owner area |
| `app/controllers/admin/` | Platform admin: onboarding firms |
| `app/controllers/internal/v1/` | API for the voice service ([../docs/API.md](../docs/API.md)) |
| `app/controllers/twilio/` | Phone fallback: forward → voicemail → SMS link |
| `app/jobs/` | SMS delivery, escalation, review requests, empty-leg expiry, data retention |
| `config/regions/` | Regional onboarding templates (places, fixed prices, tariffs) |
| `config/locales/` | German (default) and English, including all SMS texts |
| `lib/tasks/platform.rake` | `users:create`, `users:deactivate`, `tenants:list` |
