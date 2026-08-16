#!/bin/sh
set -eu

cd "$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

docker compose --profile tools config --quiet
(
  __verify_probe_host=$(./scripts/resolve-compose-value.sh BIND_ADDRESS 127.0.0.1)
  if [ "$__verify_probe_host" = 0.0.0.0 ]; then
    __verify_probe_host=127.0.0.1
  fi

  curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    "http://${__verify_probe_host}:$(./scripts/resolve-compose-value.sh HTTP_PORT 8080)/" |
    grep -q "The stack is running."
  curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    "http://${__verify_probe_host}:$(./scripts/resolve-compose-value.sh RUSTFS_API_PORT 9000)/health" >/dev/null
  curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    "http://${__verify_probe_host}:$(./scripts/resolve-compose-value.sh RUSTFS_CONSOLE_PORT 9001)/rustfs/console/health" >/dev/null
)
docker compose exec -T postgres sh -ec 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose --profile tools run --rm toolchain sh -ec 'rustc --version && cargo --version && wasmtime --version'

printf '%s\n' 'All stack checks passed.'
