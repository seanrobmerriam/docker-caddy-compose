# Caddy + Astro SSR development stack

This repository is a local Docker Compose stack with Caddy, a standalone Astro Node SSR app, PostgreSQL 18, RustFS, and an opt-in Rust/Cargo/Wasmtime toolchain. Docker Compose v2 (`docker compose`) is required for normal operation and for the verification helper.

## Start

Copy the development defaults once, then start the stack in detached mode:

```sh
cp .env.example .env
docker compose up --build -d
docker compose ps
```

With the defaults, open the Astro site at <http://127.0.0.1:8080>, the RustFS S3 API at <http://127.0.0.1:9000>, and the RustFS console at <http://127.0.0.1:9001>.

This stack is for local development. Its published ports bind to `BIND_ADDRESS=127.0.0.1` by default. Set an explicit IPv4 address in `.env` if needed; setting `BIND_ADDRESS=0.0.0.0` exposes Caddy and both RustFS ports on every host interface, so replace the example credentials first.

## Configuration

`.env.example` is the configuration contract and contains useful development defaults. The principal settings are:

- `BIND_ADDRESS`, `HTTP_PORT`, `RUSTFS_API_PORT`, and `RUSTFS_CONSOLE_PORT` control host publishing.
- `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` initialize PostgreSQL on its first run.
- `DATABASE_URL` is passed directly to Astro. It defaults to `postgresql://app:local-development-password@postgres:5432/app`.
- `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`, and `S3_BUCKET` configure the local object-store connection.
- `PNPM_VERSION` defaults to `10.12.4`; `WASMTIME_VERSION` defaults to `47.0.3`. Compose passes them to the Astro and toolchain image builds, respectively.

If you change `POSTGRES_USER`, `POSTGRES_PASSWORD`, or `POSTGRES_DB`, update `DATABASE_URL` to match. Percent-encode reserved characters in its username, password, and database components; for example, the password `local:p@ss` becomes `local%3Ap%40ss` in the URL.

The pnpm override must support lockfile version 9 and the `onlyBuiltDependencies` workspace setting. The default `10.12.4` is the tested version; the policy permits `esbuild` and `sharp`, and a clean install exercises the required `esbuild` postinstall. Regenerate and review the lockfile and build-policy file before selecting an incompatible pnpm release.

## Toolchain

The tooling container is profile-gated, so it is not part of normal startup:

```sh
docker compose --profile tools run --rm toolchain rustc --version
docker compose --profile tools run --rm toolchain cargo --version
docker compose --profile tools run --rm toolchain wasmtime --version
docker compose --profile tools run --rm toolchain
```

Files under `workspace/` appear at `/workspace`. Cargo registry and Git caches use named volumes.

## Verify

With the stack running:

```sh
./scripts/verify.sh
```

The verifier asks `docker compose config --environment` for the same resolved interpolation environment Compose uses, including shell precedence and quoted, commented, spaced, or interpolated `.env` syntax. Empty or absent values retain the `${VAR:-default}` defaults from `compose.yaml`. Its HTTP probes use connection and overall timeouts.

The standalone `docker-compose config --quiet` command can be used only as a local static-validation fallback on hosts without the v2 plugin; startup, value resolution, profiles, and verification target Compose v2.

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

Stop containers while retaining data:

```sh
docker compose down
```

To permanently remove this project's PostgreSQL databases, RustFS objects, Caddy state, and Cargo caches, run the explicitly destructive command:

```sh
docker compose down --volumes
```
