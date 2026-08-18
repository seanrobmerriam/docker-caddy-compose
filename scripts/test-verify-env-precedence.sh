#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/verify-env.XXXXXX")
cleanup() {
  status=$?
  rm -rf "$test_root"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_root/bin" "$test_root/scripts"
cp "$repo_dir/scripts/verify.sh" "$test_root/scripts/verify.sh"
cp "$repo_dir/scripts/resolve-compose-value.sh" "$test_root/scripts/resolve-compose-value.sh"
chmod +x "$test_root/scripts/verify.sh" "$test_root/scripts/resolve-compose-value.sh"

cat >"$test_root/.env" <<'EOF'
# Compose must own parsing of quotes, comments, whitespace, and interpolation.
BASE_HTTP_PORT=18181
PUBLIC_BIND_ADDRESS=0.0.0.0
HTTP_PORT="${BASE_HTTP_PORT}" # interpolated and quoted
HTTPS_PORT=18444
RUSTFS_BIND_ADDRESS=0.0.0.0
RUSTFS_API_PORT='19002' # single-quoted
RUSTFS_CONSOLE_PORT=19003   # unquoted with a comment
QUOTED_VALUE="quoted value # literal"
SPACED_VALUE=unquoted value with spaces # comment
INTERPOLATED_VALUE="${QUOTED_VALUE}-suffix"
EMPTY_VALUE=
EOF

cat >"$test_root/compose-dotenv.env" <<'EOF'
BASE_HTTP_PORT=18181
EMPTY_VALUE=
HTTP_PORT=18181
HTTPS_PORT=18444
INTERPOLATED_VALUE=quoted value # literal-suffix
PUBLIC_BIND_ADDRESS=0.0.0.0
QUOTED_VALUE=quoted value # literal
RUSTFS_BIND_ADDRESS=0.0.0.0
RUSTFS_API_PORT=19002
RUSTFS_CONSOLE_PORT=19003
SPACED_VALUE=unquoted value with spaces
EOF

cat >"$test_root/compose-shell.env" <<'EOF'
HTTP_PORT=18180
HTTPS_PORT=18443
PUBLIC_BIND_ADDRESS=192.0.2.10
RUSTFS_BIND_ADDRESS=192.0.2.11
RUSTFS_API_PORT=19000
RUSTFS_CONSOLE_PORT=19001
EOF

cat >"$test_root/compose-empty.env" <<'EOF'
HTTP_PORT=
HTTPS_PORT=
PUBLIC_BIND_ADDRESS=
RUSTFS_BIND_ADDRESS=
RUSTFS_API_PORT=
RUSTFS_CONSOLE_PORT=
EOF

cat >"$test_root/bin/docker" <<'EOF'
#!/bin/sh
if [ "${1-}" = compose ] && [ "${2-}" = version ]; then
  [ "${MOCK_COMPOSE_UNAVAILABLE:-0}" = 1 ] && exit 1
  exit 0
fi

if [ "${1-}" = compose ] && [ "${2-}" = config ] && [ "${3-}" = --environment ]; then
  if [ "${MOCK_COMPOSE_CONFIG_FAILURE:-0}" = 1 ]; then
    printf '%s\n' 'mock Compose configuration failure' >&2
    exit 7
  fi
  awk \
    -v public_bind="${MOCK_PUBLIC_BIND_ADDRESS-}" \
    -v rustfs_bind="${MOCK_RUSTFS_BIND_ADDRESS-}" \
    -v override_binds="${MOCK_OVERRIDE_BINDS:-0}" '
      override_binds && /^PUBLIC_BIND_ADDRESS=/ {
        print "PUBLIC_BIND_ADDRESS=" public_bind
        public_seen = 1
        next
      }
      override_binds && /^RUSTFS_BIND_ADDRESS=/ {
        print "RUSTFS_BIND_ADDRESS=" rustfs_bind
        rustfs_seen = 1
        next
      }
      { print }
      END {
        if (override_binds && !public_seen) print "PUBLIC_BIND_ADDRESS=" public_bind
        if (override_binds && !rustfs_seen) print "RUSTFS_BIND_ADDRESS=" rustfs_bind
      }
    ' "$COMPOSE_ENV_OUTPUT"
  exit 0
fi

printf 'args=%s | PUBLIC_BIND_ADDRESS=%s HTTP_PORT=%s HTTPS_PORT=%s RUSTFS_BIND_ADDRESS=%s RUSTFS_API_PORT=%s RUSTFS_CONSOLE_PORT=%s POSTGRES_USER=%s COMPOSE_PROJECT_NAME=%s key=%s line=%s\n' \
  "$*" "${PUBLIC_BIND_ADDRESS-unset}" "${HTTP_PORT-unset}" "${HTTPS_PORT-unset}" \
  "${RUSTFS_BIND_ADDRESS-unset}" "${RUSTFS_API_PORT-unset}" "${RUSTFS_CONSOLE_PORT-unset}" \
  "${POSTGRES_USER-unset}" "${COMPOSE_PROJECT_NAME-unset}" "${key-unset}" "${line-unset}" >>"$VERIFY_LOG"
EOF
chmod +x "$test_root/bin/docker"

cat >"$test_root/bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$VERIFY_CURL_LOG"
printf '%s\n' 'The stack is running.'
EOF
chmod +x "$test_root/bin/curl"

VERIFY_LOG="$test_root/docker-shell.log" \
  VERIFY_CURL_LOG="$test_root/curl-shell.log" \
  COMPOSE_ENV_OUTPUT="$test_root/compose-shell.env" \
  PATH="$test_root/bin:$PATH" \
  PUBLIC_BIND_ADDRESS=192.0.2.10 \
  HTTP_PORT=18180 \
  HTTPS_PORT=18443 \
  RUSTFS_BIND_ADDRESS=192.0.2.11 \
  RUSTFS_API_PORT=19000 \
  RUSTFS_CONSOLE_PORT=19001 \
  POSTGRES_USER=caller-user \
  COMPOSE_PROJECT_NAME=caller-project \
  key=caller-key \
  line=caller-line \
  "$test_root/scripts/verify.sh" >/dev/null

env -i \
  VERIFY_LOG="$test_root/docker-dotenv.log" \
  VERIFY_CURL_LOG="$test_root/curl-dotenv.log" \
  COMPOSE_ENV_OUTPUT="$test_root/compose-dotenv.env" \
  PATH="$test_root/bin:$PATH" \
  "$test_root/scripts/verify.sh" >/dev/null

VERIFY_LOG="$test_root/docker-empty.log" \
  VERIFY_CURL_LOG="$test_root/curl-empty.log" \
  COMPOSE_ENV_OUTPUT="$test_root/compose-empty.env" \
  PATH="$test_root/bin:$PATH" \
  PUBLIC_BIND_ADDRESS= \
  HTTP_PORT= \
  HTTPS_PORT= \
  RUSTFS_BIND_ADDRESS= \
  RUSTFS_API_PORT= \
  RUSTFS_CONSOLE_PORT= \
  POSTGRES_USER=caller-user \
  COMPOSE_PROJECT_NAME=caller-project \
  key=caller-key \
  line=caller-line \
  "$test_root/scripts/verify.sh" >/dev/null

expected_environment='PUBLIC_BIND_ADDRESS=192.0.2.10 HTTP_PORT=18180 HTTPS_PORT=18443 RUSTFS_BIND_ADDRESS=192.0.2.11 RUSTFS_API_PORT=19000 RUSTFS_CONSOLE_PORT=19001 POSTGRES_USER=caller-user COMPOSE_PROJECT_NAME=caller-project key=caller-key line=caller-line'
test "$(wc -l <"$test_root/docker-shell.log" | tr -d ' ')" = 3
while IFS= read -r captured; do
  case $captured in
    *"$expected_environment") ;;
    *)
      printf 'unexpected Docker environment: %s\n' "$captured" >&2
      exit 1
      ;;
  esac
done <"$test_root/docker-shell.log"

assert_curl_log() {
  log=$1
  public_host=$2
  http_port=$3
  https_port=$4
  rustfs_host=$5
  rustfs_api_port=$6
  rustfs_console_port=$7
  curl_options='--fail --silent --show-error --connect-timeout 5 --max-time 15 --noproxy *'

  test "$(sed -n '1p' "$log")" = "$curl_options --resolve recover.works:${http_port}:${public_host} http://recover.works:${http_port}/"
  test "$(sed -n '2p' "$log")" = "$curl_options http://${rustfs_host}:${rustfs_api_port}/health/ready"
  test "$(sed -n '3p' "$log")" = "$curl_options http://${rustfs_host}:${rustfs_console_port}/rustfs/console/health"
  test "$(sed -n '4p' "$log")" = "$curl_options --resolve recover.works:${https_port}:${public_host} https://recover.works:${https_port}/"
  test "$(sed -n '5p' "$log")" = "$curl_options --resolve www.recover.works:${https_port}:${public_host} https://www.recover.works:${https_port}/"
  test "$(sed -n '6p' "$log")" = "$curl_options --resolve app.recover.works:${https_port}:${public_host} https://app.recover.works:${https_port}/"
  test "$(sed -n '7p' "$log")" = "$curl_options --resolve next.recover.works:${https_port}:${public_host} https://next.recover.works:${https_port}/"
  test "$(sed -n '8p' "$log")" = "$curl_options --resolve s3.recover.works:${https_port}:${public_host} https://s3.recover.works:${https_port}/health/ready"
  test "$(sed -n '9p' "$log")" = "$curl_options --resolve s3-admin.recover.works:${https_port}:${public_host} https://s3-admin.recover.works:${https_port}/rustfs/console/health"
  test "$(wc -l <"$log" | tr -d ' ')" = 9
}

assert_curl_log "$test_root/curl-shell.log" 192.0.2.10 18180 18443 192.0.2.11 19000 19001

empty_expected_environment='PUBLIC_BIND_ADDRESS= HTTP_PORT= HTTPS_PORT= RUSTFS_BIND_ADDRESS= RUSTFS_API_PORT= RUSTFS_CONSOLE_PORT= POSTGRES_USER=caller-user COMPOSE_PROJECT_NAME=caller-project key=caller-key line=caller-line'
while IFS= read -r captured; do
  case $captured in
    *"$empty_expected_environment") ;;
    *)
      printf 'unexpected Docker environment for empty overrides: %s\n' "$captured" >&2
      exit 1
      ;;
  esac
done <"$test_root/docker-empty.log"
assert_curl_log "$test_root/curl-empty.log" 127.0.0.1 80 443 127.0.0.1 9000 9001

assert_curl_log "$test_root/curl-dotenv.log" 127.0.0.1 18181 18444 127.0.0.1 19002 19003

run_wildcard_case() {
  label=$1
  wildcard=$2
  env -i \
    VERIFY_LOG="$test_root/docker-wildcard-${label}.log" \
    VERIFY_CURL_LOG="$test_root/curl-wildcard-${label}.log" \
    COMPOSE_ENV_OUTPUT="$test_root/compose-dotenv.env" \
    MOCK_OVERRIDE_BINDS=1 \
    MOCK_PUBLIC_BIND_ADDRESS="$wildcard" \
    MOCK_RUSTFS_BIND_ADDRESS="$wildcard" \
    PATH="$test_root/bin:$PATH" \
    "$test_root/scripts/verify.sh" >/dev/null
  assert_curl_log "$test_root/curl-wildcard-${label}.log" 127.0.0.1 18181 18444 127.0.0.1 19002 19003
}

run_wildcard_case ipv4 0.0.0.0
run_wildcard_case ipv6 '::'
run_wildcard_case bracketed-ipv6 '[::]'
run_wildcard_case asterisk '*'

resolver="$test_root/scripts/resolve-compose-value.sh"
compose_output="$test_root/compose-dotenv.env"
resolver_path="$test_root/bin:$PATH"
test "$(COMPOSE_ENV_OUTPUT="$compose_output" PATH="$resolver_path" "$resolver" QUOTED_VALUE fallback)" = 'quoted value # literal'
test "$(COMPOSE_ENV_OUTPUT="$compose_output" PATH="$resolver_path" "$resolver" SPACED_VALUE fallback)" = 'unquoted value with spaces'
test "$(COMPOSE_ENV_OUTPUT="$compose_output" PATH="$resolver_path" "$resolver" INTERPOLATED_VALUE fallback)" = 'quoted value # literal-suffix'
test "$(COMPOSE_ENV_OUTPUT="$compose_output" PATH="$resolver_path" "$resolver" EMPTY_VALUE fallback)" = fallback
test "$(COMPOSE_ENV_OUTPUT="$compose_output" PATH="$resolver_path" "$resolver" ABSENT_VALUE fallback)" = fallback

if COMPOSE_ENV_OUTPUT="$compose_output" MOCK_COMPOSE_UNAVAILABLE=1 PATH="$resolver_path" \
  "$resolver" HTTP_PORT 8080 >"$test_root/unavailable.out" 2>"$test_root/unavailable.err"; then
  printf '%s\n' 'resolver unexpectedly succeeded without Docker Compose v2' >&2
  exit 1
fi
rg -q 'Docker Compose v2 is required' "$test_root/unavailable.err"

if COMPOSE_ENV_OUTPUT="$compose_output" MOCK_COMPOSE_CONFIG_FAILURE=1 PATH="$resolver_path" \
  "$resolver" HTTP_PORT 8080 >"$test_root/config-failure.out" 2>"$test_root/config-failure.err"; then
  printf '%s\n' 'resolver unexpectedly succeeded after Compose configuration failure' >&2
  exit 1
fi
rg -q 'Could not resolve HTTP_PORT from Docker Compose configuration' "$test_root/config-failure.err"

! rg -n -- '--env-file|(^|[[:space:]])(source|\.)[[:space:]]+\.?/?.env' "$repo_dir/README.md"
