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
HTTP_PORT="${BASE_HTTP_PORT}" # interpolated and quoted
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
INTERPOLATED_VALUE=quoted value # literal-suffix
QUOTED_VALUE=quoted value # literal
RUSTFS_API_PORT=19002
RUSTFS_CONSOLE_PORT=19003
SPACED_VALUE=unquoted value with spaces
EOF

cat >"$test_root/compose-shell.env" <<'EOF'
HTTP_PORT=18180
RUSTFS_API_PORT=19000
RUSTFS_CONSOLE_PORT=19001
EOF

cat >"$test_root/compose-empty.env" <<'EOF'
HTTP_PORT=
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
  cat "$COMPOSE_ENV_OUTPUT"
  exit 0
fi

printf 'args=%s | HTTP_PORT=%s RUSTFS_API_PORT=%s RUSTFS_CONSOLE_PORT=%s POSTGRES_USER=%s COMPOSE_PROJECT_NAME=%s key=%s line=%s\n' \
  "$*" "${HTTP_PORT-unset}" "${RUSTFS_API_PORT-unset}" "${RUSTFS_CONSOLE_PORT-unset}" \
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
  HTTP_PORT=18180 \
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
  HTTP_PORT= \
  RUSTFS_API_PORT= \
  RUSTFS_CONSOLE_PORT= \
  POSTGRES_USER=caller-user \
  COMPOSE_PROJECT_NAME=caller-project \
  key=caller-key \
  line=caller-line \
  "$test_root/scripts/verify.sh" >/dev/null

expected_environment='HTTP_PORT=18180 RUSTFS_API_PORT=19000 RUSTFS_CONSOLE_PORT=19001 POSTGRES_USER=caller-user COMPOSE_PROJECT_NAME=caller-project key=caller-key line=caller-line'
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

curl_options='--fail --silent --show-error --connect-timeout 5 --max-time 10'
test "$(sed -n '1p' "$test_root/curl-shell.log")" = "$curl_options http://127.0.0.1:18180/"
test "$(sed -n '2p' "$test_root/curl-shell.log")" = "$curl_options http://127.0.0.1:19000/health"
test "$(sed -n '3p' "$test_root/curl-shell.log")" = "$curl_options http://127.0.0.1:19001/rustfs/console/health"

empty_expected_environment='HTTP_PORT= RUSTFS_API_PORT= RUSTFS_CONSOLE_PORT= POSTGRES_USER=caller-user COMPOSE_PROJECT_NAME=caller-project key=caller-key line=caller-line'
while IFS= read -r captured; do
  case $captured in
    *"$empty_expected_environment") ;;
    *)
      printf 'unexpected Docker environment for empty overrides: %s\n' "$captured" >&2
      exit 1
      ;;
  esac
done <"$test_root/docker-empty.log"
test "$(sed -n '1p' "$test_root/curl-empty.log")" = "$curl_options http://127.0.0.1:8080/"
test "$(sed -n '2p' "$test_root/curl-empty.log")" = "$curl_options http://127.0.0.1:9000/health"
test "$(sed -n '3p' "$test_root/curl-empty.log")" = "$curl_options http://127.0.0.1:9001/rustfs/console/health"

test "$(sed -n '1p' "$test_root/curl-dotenv.log")" = "$curl_options http://127.0.0.1:18181/"
test "$(sed -n '2p' "$test_root/curl-dotenv.log")" = "$curl_options http://127.0.0.1:19002/health"
test "$(sed -n '3p' "$test_root/curl-dotenv.log")" = "$curl_options http://127.0.0.1:19003/rustfs/console/health"

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
