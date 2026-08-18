#!/bin/sh
set -eu

cd "$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

docker compose --profile tools config --quiet
(
  __verify_public_probe_host=$(./scripts/resolve-compose-value.sh PUBLIC_BIND_ADDRESS 0.0.0.0)
  __verify_rustfs_probe_host=$(./scripts/resolve-compose-value.sh RUSTFS_BIND_ADDRESS 127.0.0.1)
  __verify_http_port=$(./scripts/resolve-compose-value.sh HTTP_PORT 80)
  __verify_https_port=$(./scripts/resolve-compose-value.sh HTTPS_PORT 443)
  __verify_rustfs_api_port=$(./scripts/resolve-compose-value.sh RUSTFS_API_PORT 9000)
  __verify_rustfs_console_port=$(./scripts/resolve-compose-value.sh RUSTFS_CONSOLE_PORT 9001)

  case $__verify_public_probe_host in
    0.0.0.0|'::'|'[::]'|'*') __verify_public_probe_host=127.0.0.1 ;;
  esac
  case $__verify_rustfs_probe_host in
    0.0.0.0|'::'|'[::]'|'*') __verify_rustfs_probe_host=127.0.0.1 ;;
  esac

  curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --noproxy '*' \
    --resolve "recover.works:${__verify_http_port}:${__verify_public_probe_host}" \
    "http://recover.works:${__verify_http_port}/" >/dev/null
  curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --noproxy '*' \
    "http://${__verify_rustfs_probe_host}:${__verify_rustfs_api_port}/health/ready" >/dev/null
  curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --noproxy '*' \
    "http://${__verify_rustfs_probe_host}:${__verify_rustfs_console_port}/rustfs/console/health" >/dev/null

  __verify_https_route() {
    __verify_https_host=$1
    __verify_https_path=$2
    curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --noproxy '*' \
      --resolve "${__verify_https_host}:${__verify_https_port}:${__verify_public_probe_host}" \
      "https://${__verify_https_host}:${__verify_https_port}${__verify_https_path}" >/dev/null
  }

  __verify_https_route recover.works /
  __verify_https_route www.recover.works /
  __verify_https_route app.recover.works /
  __verify_https_route next.recover.works /
  __verify_https_route s3.recover.works /health/ready
  __verify_https_route s3-admin.recover.works /rustfs/console/health
)
docker compose exec -T postgres sh -ec 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose --profile tools run --rm toolchain sh -ec 'rustc --version && cargo --version && wasmtime --version'

printf '%s\n' 'All stack checks passed.'
