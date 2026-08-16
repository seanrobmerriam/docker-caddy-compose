### Task 4: Add acceptance verification and operator documentation

**Files:**
- Create: `scripts/verify.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: running Compose services and configuration from Tasks 1–3.
- Produces: one verification command, `./scripts/verify.sh`, and complete operator instructions.

- [ ] **Step 1: Write the acceptance script**

Create `scripts/verify.sh`:

```sh
#!/bin/sh
set -eu

http_port="${HTTP_PORT:-8080}"
rustfs_api_port="${RUSTFS_API_PORT:-9000}"
rustfs_console_port="${RUSTFS_CONSOLE_PORT:-9001}"

docker compose config --quiet
curl --fail --silent --show-error "http://localhost:${http_port}/" | grep -q "The stack is running."
curl --fail --silent --show-error "http://localhost:${rustfs_api_port}/health" >/dev/null
curl --fail --silent --show-error "http://localhost:${rustfs_console_port}/rustfs/console/health" >/dev/null
docker compose exec -T postgres sh -ec 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose run --rm toolchain sh -ec 'rustc --version && cargo --version && wasmtime --version'

printf '%s\n' 'All stack checks passed.'
```

Run `chmod +x scripts/verify.sh`.

- [ ] **Step 2: Run the script before startup to verify it fails**

Run:

```bash
./scripts/verify.sh
```

Expected: FAIL when the HTTP probe cannot connect because the stack is not running.

- [ ] **Step 3: Document the operator workflow**

Create `README.md` with these exact sections and commands:

````markdown
# Caddy + Astro SSR development stack

Local Docker Compose environment containing Caddy, Astro SSR, PostgreSQL, RustFS, and a separate Rust/Cargo/Wasmtime toolchain.

## Start

```sh
cp .env.example .env
docker compose up --build -d
docker compose ps
```

Open the Astro site at <http://localhost:8080>, the RustFS S3 API at <http://localhost:9000>, and the RustFS console at <http://localhost:9001>. Change these ports in `.env`.

## Toolchain

```sh
docker compose run --rm toolchain rustc --version
docker compose run --rm toolchain cargo --version
docker compose run --rm toolchain wasmtime --version
docker compose run --rm toolchain
```

Files under `workspace/` are available at `/workspace` in the toolchain container. Cargo registry and Git caches use named volumes.

## Verify

```sh
./scripts/verify.sh
```

## Configuration

`.env.example` contains development-only credentials. Replace them before exposing any service outside your machine. Astro receives `DATABASE_URL`, `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `S3_BUCKET` inside its container.

## Stop and reset

Stop containers while retaining data:

```sh
docker compose down
```

Delete containers and all named-volume data:

```sh
docker compose down --volumes
```

The second command permanently removes PostgreSQL databases, RustFS objects, Caddy state, and Cargo caches created by this project.
````

- [ ] **Step 4: Start and verify the complete stack**

Run:

```bash
docker compose up --build -d
docker compose ps
./scripts/verify.sh
```

Expected: all four normal services report running/healthy, all probes succeed, the three tool versions print, and the script ends with `All stack checks passed.`

- [ ] **Step 5: Verify persistence without deleting volumes**

Run:

```bash
docker compose exec -T postgres psql -U app -d app -c 'create table if not exists stack_probe (id integer primary key); insert into stack_probe values (1) on conflict do nothing;'
docker run --rm --network docker-caddy-astro_default --entrypoint sh minio/mc -ec 'mc alias set local http://rustfs:9000 rustfsadmin rustfsadmin && mc mb --ignore-existing local/app && printf persisted | mc pipe local/app/persistence-check.txt'
docker compose down
docker compose up -d
docker compose exec -T postgres psql -U app -d app -tAc 'select count(*) from stack_probe where id = 1;'
docker run --rm --network docker-caddy-astro_default --entrypoint sh minio/mc -ec 'mc alias set local http://rustfs:9000 rustfsadmin rustfsadmin && mc stat local/app/persistence-check.txt'
```

Expected: PostgreSQL prints `1` and `mc stat` reports the persisted RustFS object.

- [ ] **Step 6: Commit verification and documentation**

```bash
git add scripts/verify.sh README.md
git commit -m "docs: add stack verification and usage guide"
```
