# RideDesk: the revenue engine for local taxi firms

RideDesk is a multi-tenant platform that helps small taxi firms in Liechtenstein
and the Rhine valley earn more. It doesn't do that by buying more Google clicks.
It fixes the places where those firms lose bookings today:

| Where revenue leaks today | What RideDesk does |
|---|---|
| The dispatcher is driving and can't pick up, so the caller rings the next firm | An **AI phone agent** answers overflow and night calls. It quotes the official price and books the ride. If anything goes wrong, the call goes to the dispatcher, then voicemail, then an SMS with a booking link. A call never just dies. |
| There's no way to book online, only a phone number | A **booking page for each firm** with live fixed prices (Vaduz → Zurich Airport CHF 290), an SMS confirmation, and a status page the customer can cancel from |
| Bookings arrive while the dispatcher is busy and get forgotten | An **SMS with a one-tap confirm link** to the dispatcher's mobile, an automatic reminder after 10 minutes, and optional auto-confirm when a car is free |
| After a drop-off at Zurich Airport, the car drives about 1h15 home empty | **Empty-leg deals**: the empty return is published automatically as a discounted ride |
| Customers book the outward trip but not the return | **Return-trip prompts** on every airport booking, plus one-tap rebooking |
| Google ranking depends on reviews nobody asks for | An **automatic Google review request** after each completed ride |
| Ad spend is optimised for clicks, not rides | A **Google Ads offline-conversion export**, so bidding optimises for paid rides |
| Nobody can prove what the marketing earned | An **owner dashboard** showing revenue that came through the platform, calls answered by the AI, conversion, and repeat customers |

Adding a new firm is a form, not a project. Everything a firm owns is scoped
to that firm, and a regional template gives each new firm its places, fixed
prices and tariffs on day one.


Platform admin: admin@example.com / change-me-please
Firm owner: owner@example.com / change-me-please

## Architecture in one picture

```
 Caller ──phone──► Twilio number ──webhook──► voice/ (Node)  ──internal API──►  core/ (Rails)
   │  (firm line forwards                       Claude agent         Bearer token     prices, bookings,
   │   on busy / no answer)                     ConversationRelay                     SMS, dashboard
   │                                                  │ fails or hands off                  ▲
   │                                                  └──► core /twilio/voice/* ───────────┘
   │                                                       dispatcher → voicemail → SMS link
 Customer ──web──► core: /<firm>  booking page, live quote, status page
 Dispatcher ◄─SMS─ core: one-tap link /d/<token>   ·   board, phone bookings
 Owner ──────────► core: dashboard, settings, Google Ads export
```

* **`core/`**: Ruby on Rails 8.1. The single source of truth: firms, prices,
  bookings, customers, SMS, dashboards, admin. SQLite with Solid Queue, Cache
  and Cable.
* **`voice/`**: Node 22 and TypeScript. A Twilio ConversationRelay websocket
  server that runs the Claude phone agent (`claude-opus-5-5`). It has no
  database: every price and booking goes through the core.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design and
[docs/adr/](docs/adr/) for the decisions behind it.

## Quick start (Windows, development)

Prerequisites: Ruby 3.3 with DevKit (RubyInstaller) and Node 22.

```powershell
# Core
cd core
bundle install
ruby bin/rails db:prepare          # creates the DB and seeds a demo firm
$env:INTERNAL_API_TOKEN = "dev-internal-token-0123456789"
ruby bin/rails server              # http://localhost:3000

# Voice (second terminal)
cd voice
npm install
npm test
$env:CORE_API_URL = "http://localhost:3000"; $env:INTERNAL_API_TOKEN = "dev-internal-token-0123456789"
npm run check-core -- +41445550000 # checks core <-> voice without Claude
$env:ANTHROPIC_API_KEY = "sk-ant-..."
npm run simulate -- +41445550000 +41795551234   # talk to the agent in the terminal
```

Demo logins (development only): `admin@example.com` (platform) and
`owner@example.com` (firm), password `change-me-please`. The demo booking page
is at http://localhost:3000/taxi-demo.

## Tests and quality gates

| | Command | Status at handover |
|---|---|---|
| Core tests (models, services, every HTTP surface, tenant isolation) | `cd core; ruby bin/rails test` | 74 tests, 366 assertions, all passing |
| Core security scan | `ruby bin/brakeman` | 0 warnings |
| Core lint | `ruby bin/rubocop` | 0 offences |
| Voice typecheck, tests and build | `cd voice; npm run typecheck; npm test; npm run build` | 15 tests, all passing |
| Core ↔ voice integration | `npm run check-core -- <number>` | Passing against a live core, and verified idempotent |

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs all of these on
every push.

## Documentation

| Document | For |
|---|---|
| [docs/PILOT_PLAYBOOK.md](docs/PILOT_PLAYBOOK.md) | Running the pilot with the first firm, step by step |
| [docs/ONBOARDING_A_FIRM.md](docs/ONBOARDING_A_FIRM.md) | Adding firm number 2, 3, … |
| [docs/sales/PITCH_DE.md](docs/sales/PITCH_DE.md) | The one-page pitch for taxi firm owners (German) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How it works, the data model, booking lifecycle and failure handling |
| [docs/VOICE_AGENT.md](docs/VOICE_AGENT.md) | Twilio setup, languages and Swiss German, testing, costs |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Every environment variable |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Deploying, backups, monitoring, runbook |
| [docs/HOSTING_HETZNER.md](docs/HOSTING_HETZNER.md) | Hosting on Hetzner Cloud: server, firewall, DNS, backups, restore |
| [docs/API.md](docs/API.md) | The internal API between voice and core |
| [docs/DISCOVERY.md](docs/DISCOVERY.md) | Being found by Google and AI assistants; Taxi now; pushing a firm |
| [docs/SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md) | Security model, GDPR / Swiss nFADP |
| [docs/adr/](docs/adr/) | Architecture decision records |

## What's needed before going live

The software is complete for the pilot. These items need you, because they
involve accounts, money or legal review:

1. A **server and domain** (a Swiss/EU VPS). Fill in the `REPLACE` values in
   `core/config/deploy.yml` and `voice/config/deploy.yml`.
2. A **Twilio account**: one phone number for the firm (a Swiss number needs a
   regulatory address bundle), plus an SMS sender.
3. An **Anthropic API key** for the voice agent.
4. A **Google Maps API key** (Geocoding + Routes). Without it the platform
   falls back to OpenStreetMap, which needs a real contact email, and to
   estimated distances shown as "approx." prices.
5. The **firm's real prices**. The regional template is a starting point to
   agree with the owner.
6. A **legal review** of the privacy notice template and confirmation that
   Liechtenstein's taxi rules allow taking bookings on the firm's behalf (see
   [docs/SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md)).
