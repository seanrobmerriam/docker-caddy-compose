#!/bin/sh
set -eu
port="${TEST_PORT:-13000}"
response="$(mktemp)"
log="$(mktemp)"
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  [ -z "$pid" ] || wait "$pid" 2>/dev/null || true
  rm -f "$response" "$log"
}
exit_on_signal() {
  trap - EXIT HUP INT TERM
  cleanup
  exit 1
}
trap cleanup EXIT
trap exit_on_signal HUP INT TERM
HOSTNAME=127.0.0.1 PORT="$port" node .next/standalone/server.js >"$log" 2>&1 &
pid=$!
tries=0
until curl -fsS --connect-timeout 1 --max-time 2 "http://127.0.0.1:${port}/" >"$response"; do
  tries=$((tries + 1))
  [ "$tries" -lt 20 ] || { cat "$log" >&2; exit 1; }
  sleep 0.25
done
grep -q 'Next.js service is running.' "$response"
