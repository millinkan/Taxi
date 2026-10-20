# Security and privacy

## Security model

| Surface | Protection |
|---|---|
| Staff app | Rails 8 authentication (bcrypt, signed session cookie, `httponly`, `SameSite=Lax`), login rate limit, passwords ≥ 10 chars, deactivation ends all sessions, role checks (owner / dispatcher / driver / platform admin) |
| Firm data | Tenant scoping on every query ([adr/0002](adr/0002-multi-tenancy.md)), covered by isolation tests |
| Public booking form | CSRF tokens, rate limiting (10 bookings / 10 min / IP; 40 quotes / min), a honeypot field, server-side pricing only |
| Customer status page / dispatcher SMS links | 24-character random tokens (~140 bits), `Referrer-Policy: no-referrer` and `noindex` so tokens don't leak; a dispatcher link acts on that single booking only |
| Internal API | Bearer token compared in constant time; disabled when unset |
| Twilio webhooks | `X-Twilio-Signature` verified (HMAC-SHA1) in both services |
| Voice agent | Tool inputs validated with zod, prices only from the core, idempotent booking, no access to other firms (firm resolved from the dialled number) |
| Transport | TLS everywhere (kamal-proxy + Let's Encrypt, `force_ssl`) |
| Supply chain | Brakeman, bundler-audit, importmap audit, npm audit in CI |

**Secrets** are never in the repository: `config/master.key` and `.env` are
git-ignored, and Kamal reads secrets from the environment or a password
manager.

## Privacy (GDPR, Liechtenstein DSG, Swiss nFADP)

Liechtenstein is in the EEA, so the GDPR applies. Swiss customers also fall
under the Swiss nFADP. The firm is the **controller**; the platform operator
is its **processor**. **Sign a data-processing agreement (DPA) with each
firm.**

Data minimisation and retention, as built:
- Only what the ride needs: name, phone, optional email, addresses, time,
  party, flight number, notes.
- `DataRetentionJob` (daily): after the firm's retention period (default 730
  days, configurable) without a new booking, customers are anonymised, and
  call transcripts, recording links and SMS and email bodies are wiped. Bookings and
  amounts remain for accounting.
- No tracking cookies. The only cookies are the session (and the language
  preference). Attribution comes from UTM / gclid URL parameters on the
  booking itself.
- No third-party fonts or scripts on the public pages; the map library for
  live tracking is served from our own host. The live map on a customer's
  status page loads **map tiles from OpenStreetMap**: the customer's browser
  sends its IP address and the map area to openstreetmap.org, but no booking
  data (the page sends only its origin as referrer). Name this in the privacy
  notice, or switch to a self-hosted or contracted tile provider.

**Subprocessors** to list in the DPA and the privacy notice: the hosting
provider (**Hetzner Online GmbH, Germany**: servers and backup storage, see
[HOSTING_HETZNER.md](HOSTING_HETZNER.md)), Twilio (voice, SMS; US company, standard contractual clauses),
Anthropic (the language model for the phone agent; US company), Google Maps
or OpenStreetMap (address lookup), and the SMTP provider chosen for booking
emails.

**Phone calls**: the AI greeting identifies itself as a digital assistant.
Conversations are processed as text and stored as transcripts. Twilio voice
recordings are created only for voicemail. Decide with the firm's counsel
whether an explicit recording notice is needed in the greeting, and set it
under Settings › Firm › Greeting.

The privacy page (`/<firm>/privacy`) is a **template** in German and English.
Have it reviewed before go-live.

## Regulatory check before go-live (not legal advice)

- **Taxi licensing**: confirm with the Liechtenstein authority (Amt für
  Volkswirtschaft) that a technology platform may take bookings **in the
  licensed firm's name**. Bookings, prices and confirmations always come from
  the firm, and the platform never acts as the operator.
- **Cross-border pickups**: picking up in Switzerland or Austria can be
  restricted for foreign-licensed taxis (cabotage, cantonal rules, airport
  rules at Zurich). Before selling **empty legs** that start at Zurich
  Airport, confirm that the firm may pick up there. Otherwise disable empty
  legs (Settings › Firm) or limit them to legally allowed pickups.
