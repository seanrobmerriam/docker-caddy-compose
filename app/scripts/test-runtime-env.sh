#!/bin/sh
set -eu

test_port="${TEST_PORT:-14323}"
response_file="$(mktemp)"
server_log="$(mktemp)"
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$response_file" "$server_log"
}
trap cleanup EXIT HUP INT TERM

HOST=127.0.0.1 \
PORT="$test_port" \
DATABASE_URL='postgresql://app:runtime-secret@postgres:5432/app' \
S3_ENDPOINT='http://rustfs:9000' \
S3_BUCKET='runtime-bucket' \
node ./dist/server/entry.mjs >"$server_log" 2>&1 &
server_pid=$!

attempt=0
until curl --fail --silent --show-error \
  --connect-timeout 1 --max-time 2 \
  "http://127.0.0.1:${test_port}/" >"$response_file"; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 20 ]; then
    cat "$server_log" >&2
    exit 1
  fi
  sleep 0.25
done

grep -q 'PostgreSQL:</strong> postgres:5432' "$response_file"
grep -q 'RustFS S3:</strong> http://rustfs:9000' "$response_file"
grep -q 'RustFS bucket:</strong> runtime-bucket' "$response_file"
if grep -q 'runtime-secret' "$response_file"; then
  echo 'Database credentials were exposed in the rendered page.' >&2
  exit 1
fi
