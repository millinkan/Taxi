# Configuration

Both services are configured only through environment variables. The core
reads them in `core/config/initializers/platform.rb`. The voice service
validates them at boot in `voice/src/config.ts` and refuses to start if any
are wrong.

## Core (Rails)

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `RAILS_MASTER_KEY` | prod | – | Decrypts `config/credentials.yml.enc` (Rails secret key base) |
| `APP_HOST` | prod | `localhost:3000` | Platform host used in SMS links, e.g. `app.example.li` |
| `APP_PROTOCOL` | – | `https` in prod | Protocol for SMS links |
| `PLATFORM_NAME` | – | `RideDesk` | Name shown in the staff app |
| `INTERNAL_API_TOKEN` | prod | – | Shared secret with the voice service (≥ 32 random chars). With no value set, the internal API is disabled |
| `SMS_PROVIDER` | – | `twilio` in prod, `log` in dev | `twilio` or `log` (prints SMS to the log) |
| `TWILIO_ACCOUNT_SID` | prod | – | Twilio account |
| `TWILIO_AUTH_TOKEN` | prod | – | Twilio auth token: SMS sending and webhook signature checks |
| `TWILIO_SMS_FROM` | one of these two | – | Default SMS sender: a number or an alphanumeric ID (≤ 11 chars). A firm's own `sms_sender_id` overrides it |
| `TWILIO_MESSAGING_SERVICE_SID` | | – | Alternative to `TWILIO_SMS_FROM` |
| `TWILIO_WEBHOOK_BASE_URL` | recommended | – | Public base URL Twilio calls (e.g. `https://app.example.li`); pins signature validation behind proxies |
| `SMTP_ADDRESS` | recommended | – | SMTP server for booking emails and password resets (e.g. `smtp.postmarkapp.com`). Without it, production sends no booking emails and customers get SMS only |
| `SMTP_PORT` | – | `587` | STARTTLS port |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | with SMTP | – | SMTP login |
| `MAIL_FROM` | with SMTP | `bookings@<APP_HOST>` | Sender address, verified with the mail provider (SPF/DKIM). Emails show the firm's name as sender and reply to the firm's email address |
| `GOOGLE_MAPS_API_KEY` | recommended | – | Enables Google Geocoding and Routes (exact addresses and distances) |
| `GEOCODER` | – | `google` with a key, else `nominatim` | `google`, `nominatim` or `null` |
| `ROUTING` | – | `google` with a key, else `osrm` if `OSRM_URL`, else `estimate` | Distance provider |
| `OSRM_URL` | – | – | Self-hosted OSRM base URL |
| `GEOCODER_CONTACT_EMAIL` | for Nominatim | `ops@example.com` | Must be a real address. OpenStreetMap blocks placeholder contacts |
| `INDEXNOW_KEY` | – | derived from the secret key base | IndexNow ownership key (served at `/indexnow-key.txt`). See [DISCOVERY.md](DISCOVERY.md) |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | – | – | Service-account JSON (contents or file path) for submitting sitemaps to Google Search Console. Without it the Google push is skipped |
| `GOOGLE_SEARCH_CONSOLE_SITE` | – | `<APP_PROTOCOL>://<APP_HOST>/` | Search Console property for firms served under the platform host. Firms with a custom domain use `sc-domain:<domain>` |
| `DISCOVERY_AUTO_PUSH` | – | `true` (always off in tests) | Push changed pages to IndexNow and Google automatically, 5 minutes after a change and daily. See [DISCOVERY.md](DISCOVERY.md) |
| `ASSUME_SSL` / `FORCE_SSL` | – | `true` | Turn off only when testing production mode without TLS |
| `SOLID_QUEUE_IN_PUMA` | prod | – | `true` runs background jobs inside the web process |
| `RAILS_LOG_LEVEL` | – | `info` | |

Firm settings (prices, phones, policies, voice greeting…) aren't environment
variables. They live in the database and are edited in **Settings**.

## Voice (Node)

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `PORT` | – | `8080` | Listen port |
| `PUBLIC_BASE_URL` | ✔ | – | Public https URL of this service, exactly as configured in Twilio |
| `CORE_API_URL` | ✔ | – | Core URL for internal API calls (can be internal) |
| `CORE_PUBLIC_URL` | ✔ | – | Core public URL, which Twilio is redirected to for the fallback |
| `INTERNAL_API_TOKEN` | ✔ | – | Same value as in the core |
| `TWILIO_AUTH_TOKEN` | ✔ | – | Verifies webhook signatures |
| `TWILIO_VALIDATE_SIGNATURE` | – | `true` | Never `false` in production |
| `ANTHROPIC_API_KEY` | ✔ | – | Claude API key |
| `ANTHROPIC_MODEL` | – | `claude-opus-5-5` | |
| `ANTHROPIC_EFFORT` | – | `medium` | `low` / `medium` / `high`. Higher means slower replies on the phone; at `low` the agent sometimes speaks its reasoning aloud |
| `CR_LANGUAGE` | – | `de-DE` | Main ConversationRelay language |
| `CR_SECONDARY_LANGUAGE` | – | `en-US` | Language the agent can switch to |
| `CR_TTS_PROVIDER`, `CR_VOICE` | – | Twilio default | Voice selection (see VOICE_AGENT.md) |
| `CR_TRANSCRIPTION_PROVIDER`, `CR_SPEECH_MODEL` | – | Twilio default | Speech recognition selection |
| `MAX_CALL_SECONDS` | – | `600` | After this the call is handed to the dispatcher |
| `LOG_LEVEL` | – | `info` | |

Generate the shared token with, for example:
`ruby -rsecurerandom -e "puts SecureRandom.base58(40)"`.
