#!/usr/bin/env bash
# Creates the RideDesk server on Hetzner Cloud: SSH key, Cloud Firewall,
# server (Ubuntu 24.04 + cloud-init.yml) and daily Hetzner backups.
# Safe to re-run: existing resources are reused, not duplicated.
#
# Needs the hcloud CLI (https://github.com/hetznercloud/cli) with a context
# for your project:  hcloud context create ridedesk   (paste an API token)
#
#   ADMIN_IP=203.0.113.7 bash deploy/hetzner/provision.sh
#
# Settings (environment variables, with defaults):
#   ADMIN_IP     your public IP; only it may SSH in            (required)
#   SSH_PUBKEY   public key to install                         ~/.ssh/id_ed25519.pub
#   LOCATION     nbg1 Nuremberg, fsn1 Falkenstein, hel1 Helsinki  nbg1
#   SERVER_TYPE  x86, ~2 vCPU / 4 GB; list: hcloud server-type list  cx22
#   NAME         server name                                   ridedesk-1
#
# The image is built for amd64 (core/config/deploy.yml), so pick an x86 type
# (CX/CPX), not an Arm one (CAX).
set -euo pipefail

: "${ADMIN_IP:?set ADMIN_IP to your public IP address (curl -s https://ifconfig.me)}"
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
LOCATION="${LOCATION:-nbg1}"
SERVER_TYPE="${SERVER_TYPE:-cx22}"
NAME="${NAME:-ridedesk-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v hcloud > /dev/null || { echo "hcloud CLI not found"; exit 1; }
[ -f "$SSH_PUBKEY" ] || { echo "no public key at $SSH_PUBKEY (ssh-keygen -t ed25519)"; exit 1; }
hcloud server-type describe "$SERVER_TYPE" > /dev/null 2>&1 || {
  echo "server type '$SERVER_TYPE' not available. Current types:"; hcloud server-type list; exit 1; }

echo "SSH key ..."
hcloud ssh-key describe ridedesk-admin > /dev/null 2>&1 ||
  hcloud ssh-key create --name ridedesk-admin --public-key-from-file "$SSH_PUBKEY"

echo "Cloud Firewall: SSH from $ADMIN_IP only, web from everywhere ..."
if ! hcloud firewall describe ridedesk-web > /dev/null 2>&1; then
  hcloud firewall create --name ridedesk-web
  hcloud firewall add-rule ridedesk-web --direction in --protocol tcp --port 22 \
    --source-ips "$ADMIN_IP/32" --description "SSH (admin only)"
  for port in 80 443; do
    hcloud firewall add-rule ridedesk-web --direction in --protocol tcp --port "$port" \
      --source-ips 0.0.0.0/0 --source-ips ::/0 --description "web $port"
  done
  hcloud firewall add-rule ridedesk-web --direction in --protocol icmp \
    --source-ips 0.0.0.0/0 --source-ips ::/0 --description "ping"
fi

echo "Server $NAME ($SERVER_TYPE in $LOCATION) ..."
if ! hcloud server describe "$NAME" > /dev/null 2>&1; then
  hcloud server create --name "$NAME" --type "$SERVER_TYPE" --image ubuntu-24.04 --location "$LOCATION" \
    --ssh-key ridedesk-admin --firewall ridedesk-web --user-data-from-file "$HERE/cloud-init.yml" \
    --label app=ridedesk
  # Daily snapshots of the whole disk, kept 7 days (a second layer next to Litestream).
  hcloud server enable-backup "$NAME"
fi

IPV4=$(hcloud server ip "$NAME")
# Hetzner assigns a /64 network ("2a01:4f8:…::/64"); the server answers on ::1.
IPV6_NET=$(hcloud server describe "$NAME" -o format='{{.PublicNet.IPv6.IP}}')
IPV6="${IPV6_NET%/*}1"
cat <<TEXT

Done. Server $NAME: $IPV4  /  $IPV6

Next (docs/HOSTING_HETZNER.md):
  1. DNS:  app.<domain>   A $IPV4   AAAA $IPV6
           voice.<domain> A $IPV4   AAAA $IPV6
  2. Put $IPV4 into core/config/deploy.yml and voice/config/deploy.yml (REPLACE.SERVER.IP).
  3. Wait ~2 minutes for cloud-init, then:  ssh root@$IPV4 cloud-init status --wait
  4. cd core && bin/kamal setup
TEXT
