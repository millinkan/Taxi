# Hosting on Hetzner Cloud

One server runs everything: the core (Rails, SQLite, background jobs,
WebSockets) and the voice service (Node), behind Kamal's proxy with
automatic Let's Encrypt certificates. That is enough for the pilot and for
the first dozens of firms.

```
                 Hetzner Cloud Firewall: 80/443 open, 22 from your IP only
 Twilio, phones ─────────────────────────────┐
 browsers                                    ▼
                    ┌───────────── ridedesk-1 (Ubuntu 24.04) ─────────────┐
                    │ kamal-proxy  app.<domain> ──► ridedesk-core (Rails)  │
                    │   (TLS)      voice.<domain> ─► ridedesk-voice (Node) │
                    │ volume ridedesk_storage: SQLite on local NVMe        │
                    │ litestream ── every change, within seconds ──────────┼──► Object Storage (backups)
                    └──────────── daily disk snapshot (Hetzner Backups) ───┘
```

## Choices, and why

| | Choice | Why |
|---|---|---|
| Location | **Nuremberg (nbg1)**; Falkenstein (fsn1) is equivalent | Hetzner has no Swiss data centre. Germany is about 10–15 ms from Liechtenstein, so it is not noticeable for phone calls or live tracking. |
| Server | x86, about 2 vCPU / 4 GB (`cx22` by default; check `hcloud server-type list`) | The Docker image is built for amd64. Arm types (CAX) would need an arm64 build. |
| Database | SQLite on the server's local disk | Fastest option and nothing extra to run. Hetzner Volumes are network storage: slower, and not needed. |
| Backups | Litestream → Hetzner Object Storage, **plus** Hetzner Backups | Litestream sends every change within seconds, with 30 days of point-in-time restore. Hetzner Backups keep 7 daily snapshots of the whole server. |
| Firewall | Hetzner **Cloud Firewall** | Docker publishes ports past `ufw`, so a host firewall would give false confidence. |

Costs (check current prices in the Hetzner console): one small server, plus
20 % for Backups, plus Object Storage at a few euros a month. That's in the
range of 10–20 € a month in total.

## Data protection

* Liechtenstein is in the EEA (GDPR applies). Germany is in the EU, so no
  transfer mechanism is needed. Swiss customers are covered by Switzerland's
  adequacy decision for Germany.
* **Sign Hetzner's data processing agreement** (Console > account > "Data
  protection" / AVV) and list **Hetzner Online GmbH, Germany** as the hosting
  subprocessor ([SECURITY_PRIVACY.md](SECURITY_PRIVACY.md)).
* Object Storage must be in the same EU location (nbg1/fsn1/hel1).

## Step by step

### 1. Account and tools (once)
1. Create a Hetzner Cloud project, then an API token with read & write access (Security > API tokens).
2. Install the [hcloud CLI](https://github.com/hetznercloud/cli) and run `hcloud context create ridedesk`.
3. Have an SSH key: `ssh-keygen -t ed25519` if you don't have one.
4. Have a domain, for example `ridedesk.li`, with DNS you control. Hetzner DNS works.

### 2. Create the server
```bash
ADMIN_IP=$(curl -s https://ifconfig.me) bash deploy/hetzner/provision.sh
```
It creates the SSH key entry, the firewall (SSH from your IP only), the
server with [cloud-init.yml](../deploy/hetzner/cloud-init.yml) (key-only SSH,
fail2ban, automatic security updates, Docker log rotation, swap) and switches
on daily Backups. It prints the IPs and the next steps. If your IP changes,
update the firewall rule in the console.

### 3. DNS
| Name | Type | Value |
|---|---|---|
| `app.<domain>` | A / AAAA | server IPv4 / IPv6 (printed by the script) |
| `voice.<domain>` | A / AAAA | same |
| each firm's own domain, e.g. `buchen.taxi-vaduz.li` | CNAME | `app.<domain>` (also add it to `proxy.hosts` in `core/config/deploy.yml`) |

Let's Encrypt needs these records live before step 6.

### 4. Object Storage for backups
1. Console > Object Storage > create a bucket in the **same location** (e.g.
   `ridedesk-backups` in nbg1). Keep it private.
2. Create S3 credentials (access key, secret key).
3. In `core/config/deploy.yml` > `accessories.litestream`: set
   `LITESTREAM_BUCKET`, and `LITESTREAM_REGION` / `LITESTREAM_ENDPOINT` if not
   nbg1. Copy the endpoint exactly as the console shows it
   (`https://<location>.your-objectstorage.com`).

### 5. Fill in the deploy files
* `core/config/deploy.yml` and `voice/config/deploy.yml`: replace every
  `REPLACE…` (server IP, domain, registry user).
* Export the secrets listed in `core/.kamal/secrets`, including
  `LITESTREAM_ACCESS_KEY_ID` / `LITESTREAM_SECRET_ACCESS_KEY`, and
  `ANTHROPIC_API_KEY` for the voice service.
* **Commit.** Kamal tags each release with the git commit and deploys
  committed code only.

### 6. First deploy
```bash
ssh root@<server-ip> cloud-init status --wait     # first-boot setup finished
cd core
bin/kamal setup                                   # Docker, proxy, TLS, core app
bin/kamal accessory boot litestream               # start continuous backups
bin/kamal deploy -c ../voice/config/deploy.yml    # voice service
bin/kamal app exec "bin/rails users:create ROLE=platform_admin NAME='Your Name' EMAIL=you@example.com"
```
Then continue with [OPERATIONS.md](OPERATIONS.md) › First deployment, step 5
(onboard the firm, run `check-core`, set the Twilio webhooks to
`https://voice.<domain>`).

### 7. Check
* `https://app.<domain>/up` and `https://voice.<domain>/healthz` respond, with a valid certificate.
* `bin/kamal accessory logs litestream` shows `replicating to` and no errors.
* Hetzner console > server > Backups shows the first snapshot the next day.
* Book a test ride and watch the live map from a phone.

## Restoring

**The server is gone, or it's a fresh server:** run steps 2–6 on the new server,
**but before `bin/kamal setup`** restore the database into the volume:
```bash
ssh root@<new-ip>
docker volume create ridedesk_storage
docker run --rm -v ridedesk_storage:/rails/storage -v /root/litestream.yml:/etc/litestream.yml \
  -e LITESTREAM_ACCESS_KEY_ID=… -e LITESTREAM_SECRET_ACCESS_KEY=… \
  -e LITESTREAM_BUCKET=… -e LITESTREAM_REGION=nbg1 -e LITESTREAM_ENDPOINT=https://nbg1.your-objectstorage.com \
  litestream/litestream:0.3.13 restore -if-replica-exists /rails/storage/production.sqlite3
# same for /rails/storage/production_queue.sqlite3; then fix ownership for the app user:
docker run --rm -v ridedesk_storage:/s alpine chown -R 1000:1000 /s
```
(copy `core/config/litestream.yml` to `/root/litestream.yml` first). Use
`-timestamp 2026-10-20T08:00:00Z` to restore to a moment before an
accidental change.

**Small mistakes** (a firm deleted something): restore to a timestamp into a
*separate* file, inspect it with `sqlite3`, and copy back only what's needed.

**Practise a restore once during the pilot**, onto a throwaway server.

## Updates and maintenance

* Releases: `bin/kamal deploy` (zero downtime; `bin/kamal rollback <version>`).
* Security updates install automatically. Reboot for kernel updates in a
  quiet hour (`ssh root@… reboot`, about a minute of downtime; calls fall back
  to Twilio's forwarding meanwhile).
* Before risky changes: `hcloud server create-image --type snapshot ridedesk-1`.

## When to grow

The first limit is CPU during busy phone hours. Resize the server in place
(`hcloud server change-type`, a few minutes of downtime) long before anything
else. Splitting the voice service onto its own server is the next step;
moving off SQLite comes much later, see [ARCHITECTURE.md](ARCHITECTURE.md) ›
Scaling path.
