#!/usr/bin/env bash
# Runs the end-to-end scenarios against an isolated server with a fresh,
# throwaway database. Your development database is not touched.
#
#   bash e2e/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${E2E_PORT:-3070}"
CORE="$ROOT/core"
LOG="$CORE/log/e2e-server.log"

export RAILS_ENV=development
export DATABASE_URL="sqlite3:storage/e2e.sqlite3"
export E2E_BASE_URL="http://localhost:$PORT"
export APP_HOST="localhost:$PORT" APP_PROTOCOL=http
export INTERNAL_API_TOKEN="e2e-internal-token-0123456789abcdef"
export TWILIO_AUTH_TOKEN="e2e-twilio-token" TWILIO_WEBHOOK_BASE_URL="$E2E_BASE_URL"
export SMS_PROVIDER=log
export SEED_PASSWORD="${SEED_PASSWORD:-change-me-please}"

stop_server() {
  if command -v powershell.exe > /dev/null; then
    powershell.exe -NoProfile -Command "Get-NetTCPConnection -State Listen -LocalPort $PORT -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }" > /dev/null
  elif [ -f "$CORE/tmp/pids/e2e.pid" ]; then
    kill "$(cat "$CORE/tmp/pids/e2e.pid")" 2> /dev/null
  fi
  rm -f "$CORE/tmp/pids/e2e.pid"
}
trap stop_server EXIT

cd "$CORE"
stop_server
rm -f storage/e2e.sqlite3*
echo "Preparing a fresh e2e database (seeded with the demo firm) ..."
bin/rails db:prepare > /dev/null || exit 1

echo "Starting the server on $E2E_BASE_URL ..."
bin/rails server -p "$PORT" -P tmp/pids/e2e.pid > "$LOG" 2>&1 &
for _ in $(seq 1 90); do
  grep -qE "Listening|Exiting" "$LOG" 2> /dev/null && break
  sleep 1
done
grep -q "Listening" "$LOG" || { echo "server did not start, see $LOG"; exit 1; }

bin/rails runner "$ROOT/e2e/scenarios.rb"
