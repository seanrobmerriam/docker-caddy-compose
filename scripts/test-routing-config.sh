#!/bin/sh
set -eu

cd "$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

parsed=$(
  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[^[:space:]].*\{[[:space:]]*$/ {
      header = $0
      sub(/[[:space:]]*\{[[:space:]]*$/, "", header)
      count = split(header, labels, ",")
      in_site = header != ""
      for (position = 1; position <= count; position++) {
        print "host " trim(labels[position])
      }
      next
    }

    in_site && /^[[:space:]]*reverse_proxy[[:space:]]+/ {
      upstream = $0
      sub(/^[[:space:]]*reverse_proxy[[:space:]]+/, "", upstream)
      upstream = trim(upstream)
      for (position = 1; position <= count; position++) {
        print "route " trim(labels[position]) " " upstream
      }
      next
    }

    in_site && /^}[[:space:]]*$/ {
      in_site = 0
    }
  ' Caddyfile
)

expected_hosts='app.recover.works
next.recover.works
recover.works
s3-admin.recover.works
s3.recover.works
www.recover.works'
expected_routes='app.recover.works astro:4321
next.recover.works next:3000
recover.works astro:4321
s3-admin.recover.works rustfs:9001
s3.recover.works rustfs:9000
www.recover.works astro:4321'

actual_hosts=$(printf '%s\n' "$parsed" | awk '$1 == "host" { sub(/^host /, ""); print }' | LC_ALL=C sort)
actual_routes=$(printf '%s\n' "$parsed" | awk '$1 == "route" { sub(/^route /, ""); print }' | LC_ALL=C sort)

if [ "$actual_hosts" != "$expected_hosts" ]; then
  printf '%s\n%s\n' 'Caddy must contain exactly one site label for each of these six public hostnames:' "$expected_hosts" >&2
  printf '%s\n%s\n' 'Parsed site labels:' "$actual_hosts" >&2
  exit 1
fi

if [ "$actual_routes" != "$expected_routes" ]; then
  printf '%s\n%s\n' 'Caddy must contain exactly this six-route host-to-upstream mapping:' "$expected_routes" >&2
  printf '%s\n%s\n' 'Parsed host-to-upstream routes:' "$actual_routes" >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*auto_https[[:space:]]+(off|disable_certs|disable_redirects)([[:space:]]|$)' Caddyfile; then
  printf '%s\n' 'Caddy automatic HTTPS certificates and redirects must remain enabled.' >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  compose() {
    docker compose "$@"
  }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() {
    docker-compose "$@"
  }
else
  printf '%s\n' 'Docker Compose v2 or the standalone docker-compose fallback is required.' >&2
  exit 1
fi

rendered=$(compose --env-file .env.example config)

expected_rustfs_health='curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:9000/health/ready && curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:9001/rustfs/console/health'
if ! printf '%s\n' "$rendered" | grep -Fq -- "$expected_rustfs_health"; then
  printf '%s\n' 'Rendered RustFS healthcheck must use the API readiness endpoint and preserve the console health endpoint.' >&2
  exit 1
fi

assert_binding() {
  service=$1
  host_ip=$2
  target=$3
  published=$4
  if ! printf '%s\n' "$rendered" | awk \
    -v wanted_service="$service" \
    -v wanted_host_ip="$host_ip" \
    -v wanted_target="$target" \
    -v wanted_published="$published" '
      /^  [[:alnum:]_-]+:/ {
        service = $1
        sub(/:$/, "", service)
      }
      service == wanted_service && /^      - mode: ingress$/ {
        in_port = 1
        host_ip = target = published = ""
        next
      }
      in_port && /^        host_ip:/ { host_ip = $2 }
      in_port && /^        target:/ { target = $2 }
      in_port && /^        published:/ {
        published = $2
        gsub(/"/, "", published)
      }
      in_port && /^        protocol:/ {
        if (host_ip == wanted_host_ip && target == wanted_target && published == wanted_published) {
          found = 1
        }
        in_port = 0
      }
      END { exit !found }
    '
  then
    printf 'missing rendered binding %s %s:%s -> %s\n' "$service" "$host_ip" "$published" "$target" >&2
    exit 1
  fi
}

assert_binding caddy 0.0.0.0 80 80
assert_binding caddy 0.0.0.0 443 443
assert_binding rustfs 127.0.0.1 9000 9000
assert_binding rustfs 127.0.0.1 9001 9001

printf '%s\n' 'Routing configuration checks passed.'
