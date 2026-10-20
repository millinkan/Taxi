# Operations

## Environments

| | Core | Voice |
|---|---|---|
| Development | `ruby bin/rails server` (SQLite in `core/storage/`, SMS printed to the log, jobs `:async`) | `npm run dev` |
| Production | Docker via Kamal, `https://app.<domain>` | Docker via Kamal, `https://voice.<domain>` |

## First deployment

Deploy from a machine with Docker and SSH: macOS, Linux, or on Windows from
WSL2 (Ubuntu) with Docker Desktop. Kamal builds the images locally and tags
each release with the git commit, so the code must be committed first.

1. Get a VPS (2 vCPU / 4 GB is plenty for the pilot) in Switzerland or the EU,
   with Docker-ready Ubuntu and SSH key access. **On Hetzner, follow
   [HOSTING_HETZNER.md](HOSTING_HETZNER.md)**: one script creates the server,
   firewall and backups, and Litestream backs up continuously.
2. Point DNS: `app.<domain>` and `voice.<domain>` → server IP. Each firm's
   custom domain gets a CNAME to `app.<domain>` (and add it to the
   `proxy.hosts` list in `core/config/deploy.yml`).
3. Fill in the `REPLACE` values in `core/config/deploy.yml` and
   `voice/config/deploy.yml`. For booking emails, pick an SMTP provider
   (Postmark, Brevo, Amazon SES), verify the sending domain (SPF and DKIM DNS
   records), then uncomment `SMTP_ADDRESS` and `MAIL_FROM`.
4. Export the secrets listed in `core/.kamal/secrets` (or wire up your password
   manager), then:
   ```bash
   cd core
   bin/kamal setup                                   # first time: proxy, TLS, app
   bin/kamal deploy -c ../voice/config/deploy.yml    # voice service
   bin/kamal app exec "bin/rails users:create ROLE=platform_admin NAME='Your Name' EMAIL=you@example.com"
   ```
   The last command prints a generated password. Sign in at `https://app.<domain>`.
5. Onboard the pilot firm in the Admin area ([ONBOARDING_A_FIRM.md](ONBOARDING_A_FIRM.md)).
6. Run the go-live check and fix every `FAIL` line (`WARN` lines work but lose
   a feature):
   ```bash
   bin/kamal app exec "bin/rails platform:preflight"
   ```
7. Run `npm run check-core -- <firm voice number>` from your machine against
   production (with `CORE_API_URL` and `INTERNAL_API_TOKEN` set) and decline
   the test booking it creates.
8. Set up the firm's Twilio number as in [VOICE_AGENT.md](VOICE_AGENT.md)
   (webhook `https://voice.<domain>/twilio/voice/incoming`), call it once, and
   book a test ride with your own email address.

Deploy releases with `bin/kamal deploy` (core) and
`bin/kamal deploy -c ../voice/config/deploy.yml` (voice). Kamal does zero-
downtime switching and keeps the previous version (`bin/kamal rollback <version>`).

## Users

```bash
bin/kamal app exec "bin/rails users:create ROLE=dispatcher TENANT=taxi-vaduz NAME='Hans' EMAIL=hans@… PHONE=+4179…"
bin/kamal app exec "bin/rails users:deactivate EMAIL=hans@…"
bin/kamal app exec "bin/rails tenants:list"
```
Roles: `owner` (everything for the firm), `dispatcher` (board, bookings,
calls, deals), `driver` (board, start/complete rides), `platform_admin` (all
firms).

## Backups

All state is in the `ridedesk_storage` volume (SQLite files). On Hetzner the
Litestream accessory streams it to Object Storage continuously and Hetzner
Backups snapshot the server daily ([HOSTING_HETZNER.md](HOSTING_HETZNER.md) ›
Restoring). Elsewhere, back up daily and keep 30 days:

```bash
# on the server (cron, 02:30). sqlite3 .backup is safe while the app runs.
docker exec $(docker ps -qf name=ridedesk-core-web) \
  sqlite3 /rails/storage/production.sqlite3 ".backup /rails/storage/backup-$(date +%F).sqlite3"
# then copy storage/backup-*.sqlite3 off the server (restic, rclone, or the provider's snapshots)
```
**Test a restore once during the pilot**: copy a backup over
`production.sqlite3` on a staging container and start it.

## Monitoring

- **Uptime**: monitor `https://app.<domain>/up` and
  `https://voice.<domain>/healthz` every minute (UptimeRobot, Better Stack…)
  and alert by SMS.
- **Logs**: `bin/kamal logs` (core), `bin/kamal logs -c ../voice/config/deploy.yml`
  (voice; one JSON object per line).
- **Business signals** to check daily in the first weeks:
  - Calls with outcome `failed` (Dispatch › Calls): look at the transcript.
  - Messages stuck in `failed` (shown on each booking): Twilio sender or credit problem.
  - Pending bookings older than 30 minutes: the dispatcher isn't seeing SMS.

## Runbook

| Symptom | Likely cause | Action |
|---|---|---|
| Callers hear "please leave a message" all the time | Voice service down; Twilio uses the core fallback | `bin/kamal app details -c ../voice/config/deploy.yml`, check logs, redeploy. Calls are still handled by forward plus voicemail meanwhile |
| Agent answers but transfers every call | Claude API errors (key, quota) or the core's internal API is unreachable | Voice logs show `voice session failed`. Check `ANTHROPIC_API_KEY`, then run `npm run check-core` |
| Customers get no SMS | Twilio credentials, sender ID not allowed for that country, or out of credit | Booking page › messages show `failed` with the error. Fix, then re-send by confirming again |
| Prices show "approx." | No Google key, or Google quota hit, so the estimate is in use | Set or raise `GOOGLE_MAPS_API_KEY`. Fixed routes are unaffected |
| 403 on Twilio webhooks | Signature mismatch: wrong `TWILIO_AUTH_TOKEN` or URL differs from what Twilio calls | Set `TWILIO_WEBHOOK_BASE_URL` / `PUBLIC_BASE_URL` to exactly the configured URL |
