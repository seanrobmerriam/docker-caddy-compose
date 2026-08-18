# Caddy HTTPS + Astro and Next.js stack

This repository runs a production-oriented Docker Compose stack with Caddy, Astro SSR, Next.js, PostgreSQL 18, RustFS, and an opt-in Rust/Cargo/Wasmtime toolchain. Caddy terminates automatic HTTPS for six public hostnames; PostgreSQL remains internal to Compose, while RustFS's host ports remain loopback-only for administration and diagnostics.

Docker Compose v2 (`docker compose`) is required for startup and for the verification helper. The standalone `docker-compose config` command is supported only as a static configuration fallback.

## Public routes

| URL | Service | Purpose |
| --- | --- | --- |
| <https://recover.works> | `astro:4321` | Astro site |
| <https://www.recover.works> | `astro:4321` | Astro `www` alias |
| <https://app.recover.works> | `astro:4321` | Astro application alias |
| <https://next.recover.works> | `next:3000` | Next.js service |
| <https://s3.recover.works> | `rustfs:9000` | RustFS S3 API |
| <https://s3-admin.recover.works> | `rustfs:9001` | RustFS console |

The S3 API and console deliberately use dedicated domains so Caddy can proxy their root-relative paths without rewriting them. This topology supports S3 path-style addressing only: configure the endpoint as `https://s3.recover.works` and force path-style requests so object URLs use `/bucket/key`. It does not configure wildcard bucket DNS, wildcard Caddy hostnames, or `RUSTFS_SERVER_DOMAINS`, so virtual-hosted bucket URLs such as `https://bucket.s3.recover.works/key` are unsupported.

Cloudflare's proxied upload limits and connection timeouts vary by plan and may change. Check the current [Cloudflare upload limits](https://developers.cloudflare.com/fundamentals/reference/connection-limits/#upload-limits) and [connection timeout documentation](https://developers.cloudflare.com/fundamentals/reference/connection-limits/) before deployment. Keep each multipart-upload part below the current limit for the zone's plan. For requests that are too large or too long-lived for the proxy, use a separately secured DNS-only/direct S3 endpoint instead.

## Configuration and network exposure

Copy the example configuration once and replace its development credentials before starting a server:

```sh
cp .env.example .env
```

`.env.example` is the configuration contract. Its principal settings are:

- `PUBLIC_BIND_ADDRESS`, `HTTP_PORT`, and `HTTPS_PORT` publish Caddy. Their defaults are `0.0.0.0`, `80`, and `443`, so Caddy accepts public HTTP and HTTPS traffic on every IPv4 interface.
- `RUSTFS_BIND_ADDRESS`, `RUSTFS_API_PORT`, and `RUSTFS_CONSOLE_PORT` publish direct RustFS access. The bind address defaults to `127.0.0.1`; keep it loopback-only unless a separately secured private network requires otherwise.
- `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` initialize PostgreSQL on its first run. PostgreSQL has no host port.
- `DATABASE_URL` is passed to Astro and defaults to a development-only PostgreSQL URL. If you change the database values, update this URL too. Percent-encode reserved characters in its username, password, and database components.
- `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`, and `S3_BUCKET` configure Astro's internal object-store connection. Replace both example credentials before deployment.
- `PNPM_VERSION` defaults to `10.12.4`; `WASMTIME_VERSION` defaults to `47.0.3`.

Do not reuse the old shared `BIND_ADDRESS` setting. `PUBLIC_BIND_ADDRESS` and `RUSTFS_BIND_ADDRESS` are intentionally independent: the web entry point is public, but direct storage administration is not.

The tested pnpm release supports lockfile version 9. The Astro project uses `onlyBuiltDependencies` in `app/pnpm-workspace.yaml` to permit the `esbuild` and `sharp` install scripts. The Next.js project separately uses `ignoredBuiltDependencies` in `next/pnpm-workspace.yaml` for `sharp` and `unrs-resolver`; its Docker dependency stage copies that policy file before the frozen install. Regenerate and review each lockfile and workspace build-policy file before selecting an incompatible pnpm release.

## Cloudflare and Linode rollout

Use this order for the first deployment. It allows Caddy to obtain and persist its certificates before Cloudflare begins enforcing origin-certificate validation.

1. In Cloudflare DNS, create proxied (orange-cloud) `A` records for `@`, `www`, `app`, `next`, `s3`, and `s3-admin`. Point every record to `155.138.216.151`.
2. In Cloudflare Cache Rules, create a rule matching hostname `s3.recover.works` and set **Cache eligibility** to **Bypass cache**. S3 presigned URLs carry authorization in their query strings; bypassing the edge cache ensures RustFS evaluates every signed request and prevents cached or stale object responses from bypassing the intended authorization and object semantics. See Cloudflare's [Cache Rules settings](https://developers.cloudflare.com/cache/how-to/cache-rules/settings/#cache-eligibility).
3. In the Linode Cloud Firewall attached to the server, initially permit inbound TCP ports `80` and `443` from all IPv4 and IPv6 sources. This broad access is temporary so Caddy can complete its first ACME certificate issuance. Keep PostgreSQL unexposed and retain the default loopback bindings for RustFS ports `9000` and `9001`.
4. In Cloudflare SSL/TLS settings, select **Full** for the initial deployment. Do not use Flexible mode, and do not select Full (strict) yet.
5. On the server, start the stack and follow Caddy's certificate logs:

   ```sh
   docker compose up --build -d
   docker compose ps
   docker compose logs -f caddy
   ```

   Wait for Caddy to report successful certificate issuance for all six names. Caddy's `/data` and `/config` paths use named volumes, so certificate state survives container recreation.
6. In another shell, run `./scripts/verify.sh`. It sends hostname-correct HTTP and HTTPS requests directly to the configured local Caddy listener, bypassing Cloudflare via curl address overrides. This confirms the origin certificate and every route independently of the Cloudflare edge. It also checks both loopback RustFS health endpoints, PostgreSQL readiness, and the toolchain.
7. Confirm the six public HTTPS URLs through Cloudflare. Only after Caddy certificate issuance and all HTTPS probes succeed should you change Cloudflare SSL/TLS mode from **Full** to **Full (strict)**. Re-run all six public checks after the change.
8. Open <https://s3-admin.recover.works> after deployment. Sign in, then open <https://s3-admin.recover.works/config>. If the current RustFS console exposes its external S3 service endpoint on that page, set or confirm the value is exactly `https://s3.recover.works`; RustFS versions can differ, so use the setting presented by the current `/config` page rather than assuming a UI label. Manually sign out and back in, list the existing buckets, create a temporary bucket, upload a test object, and download the same object. Confirm the console remains on `s3-admin.recover.works` and its public S3 operations use `s3.recover.works`, then remove the temporary object and bucket if they are no longer needed.
9. Harden the origin after Full (strict) is working. Restrict Linode inbound TCP `80` and `443` sources to Cloudflare's maintained, published [IPv4 and IPv6 ranges](https://www.cloudflare.com/ips/) and keep the firewall synchronized with that list; do not copy a fixed range list into this repository. Alternatively, deploy and enforce [Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/) at Caddy. Leaving `80` and `443` unrestricted lets anyone who learns the Linode IP bypass Cloudflare and its protections. After either restriction, test all six domains through Cloudflare and perform a controlled Caddy renewal test; continue monitoring Caddy's certificate logs through subsequent renewals so firewall or origin-authentication changes cannot silently break renewal.
10. Remove the obsolete inbound port `8080` rule from the Linode Cloud Firewall after the 80/443 rollout is verified.

Do not make the DNS or firewall cutover until the new `.env` secrets are in place. If certificate issuance fails, leave Cloudflare on Full, inspect `docker compose logs -f caddy`, and keep ports 80/443 reachable while correcting DNS or firewall configuration.

## Verify

With the stack running:

```sh
./scripts/verify.sh
```

The verifier asks `docker compose config --environment` for the same resolved interpolation environment Compose uses, including shell precedence and quoted, commented, spaced, or interpolated `.env` syntax. Empty or absent values retain the `${VAR:-default}` defaults from `compose.yaml`: public HTTP/HTTPS use ports 80/443, and RustFS uses ports 9000/9001. Wildcard listener values such as `0.0.0.0` are mapped to loopback only for local probes; the configured published bindings are not changed.

The verification sequence checks:

- Caddy's local HTTP listener and all six hostname-correct HTTPS routes;
- the direct RustFS S3 and console health endpoints on `RUSTFS_BIND_ADDRESS`;
- PostgreSQL readiness; and
- the profile-gated Rust, Cargo, and Wasmtime toolchain.

For static checks that do not require a running stack:

```sh
./scripts/test-routing-config.sh
./scripts/test-verify-env-precedence.sh
docker-compose config --quiet
docker run --rm -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

The routing check prefers Docker Compose v2 and falls back to standalone `docker-compose` for static rendering. The Caddy command performs a repeatable native configuration validation in the official image; it may pull `caddy:2-alpine` when the image is not already local.

## Toolchain

The tooling container is profile-gated and is not part of normal startup:

```sh
docker compose --profile tools run --rm toolchain rustc --version
docker compose --profile tools run --rm toolchain cargo --version
docker compose --profile tools run --rm toolchain wasmtime --version
docker compose --profile tools run --rm toolchain
```

Files under `workspace/` appear at `/workspace`. Cargo registry and Git caches use named volumes.

## Persistence check

The named PostgreSQL and RustFS volumes survive container recreation. This non-destructive check derives the actual Compose network and passes resolved RustFS values explicitly into the temporary client container:

```sh
postgres_container="$(docker compose ps -q postgres)"
compose_network="$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$postgres_container" | sed -n '1p')"
test -n "$compose_network"
docker compose exec -T postgres sh -ec 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '"'"'create table if not exists stack_probe (id integer primary key); insert into stack_probe values (1) on conflict do nothing;'"'"''
RUSTFS_ACCESS_KEY="$(./scripts/resolve-compose-value.sh RUSTFS_ACCESS_KEY '')"
RUSTFS_SECRET_KEY="$(./scripts/resolve-compose-value.sh RUSTFS_SECRET_KEY '')"
S3_BUCKET="$(./scripts/resolve-compose-value.sh S3_BUCKET app)"
test -n "$RUSTFS_ACCESS_KEY" && test -n "$RUSTFS_SECRET_KEY" || { printf '%s\n' 'Set RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY in .env before running the persistence check.' >&2; exit 1; }
docker run --rm --network "$compose_network" -e RUSTFS_ACCESS_KEY="$RUSTFS_ACCESS_KEY" -e RUSTFS_SECRET_KEY="$RUSTFS_SECRET_KEY" -e S3_BUCKET="$S3_BUCKET" --entrypoint sh minio/mc -ec 'mc alias set local http://rustfs:9000 "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" && mc mb --ignore-existing local/"$S3_BUCKET" && printf persisted | mc pipe local/"$S3_BUCKET"/persistence-check.txt'
docker compose down
docker compose up -d
docker compose exec -T postgres sh -ec 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc '"'"'select count(*) from stack_probe where id = 1;'"'"''
RUSTFS_ACCESS_KEY="$(./scripts/resolve-compose-value.sh RUSTFS_ACCESS_KEY '')"
RUSTFS_SECRET_KEY="$(./scripts/resolve-compose-value.sh RUSTFS_SECRET_KEY '')"
S3_BUCKET="$(./scripts/resolve-compose-value.sh S3_BUCKET app)"
test -n "$RUSTFS_ACCESS_KEY" && test -n "$RUSTFS_SECRET_KEY" || { printf '%s\n' 'Set RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY in .env before running the persistence check.' >&2; exit 1; }
docker run --rm --network "$compose_network" -e RUSTFS_ACCESS_KEY="$RUSTFS_ACCESS_KEY" -e RUSTFS_SECRET_KEY="$RUSTFS_SECRET_KEY" -e S3_BUCKET="$S3_BUCKET" --entrypoint sh minio/mc -ec 'mc alias set local http://rustfs:9000 "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" && mc stat local/"$S3_BUCKET"/persistence-check.txt'
```

PostgreSQL should print `1`, and `mc stat` should report the persisted object.

## Stop and reset

Stop containers while retaining data and Caddy certificates:

```sh
docker compose down
```

To permanently remove this project's PostgreSQL databases, RustFS objects, Caddy certificates and state, and Cargo caches, run:

```sh
docker compose down --volumes
```

The volume-removal command is destructive and cannot be undone from this stack.
