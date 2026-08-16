# Docker Caddy Astro Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a one-command local Docker Compose stack with Caddy, an Astro SSR site managed by pnpm, PostgreSQL, RustFS, and an on-demand Rust/Cargo/Wasmtime toolchain.

**Architecture:** Caddy is the public HTTP entry point and proxies to an Astro Node SSR container. Astro reaches PostgreSQL and RustFS by Compose service name, while persistent service data is held in named volumes. A profile-gated tooling container isolates the latest stable Rust/Cargo and Wasmtime from the web runtime.

**Tech Stack:** Docker Compose, Caddy 2, Astro 7, `@astrojs/node`, Node.js 24, pnpm/Corepack, PostgreSQL 18, RustFS, Rust stable, Wasmtime

## Global Constraints

- The normal stack must start with `docker compose up --build`.
- Astro dependencies must be managed with pnpm.
- The Astro application must use SSR with the official Node adapter in standalone mode.
- Rust/Cargo and Wasmtime must live in a separate on-demand container.
- PostgreSQL and RustFS data must survive container recreation in named volumes.
- Local credentials must be configurable through `.env`, with development defaults documented in `.env.example`.
- Production TLS, external secret management, migrations, bucket initialization, authentication, and observability are out of scope.

## File Map

- `app/package.json`: Astro scripts and dependency declarations generated from `astro@latest`.
- `app/pnpm-lock.yaml`: reproducible pnpm dependency graph.
- `app/astro.config.mjs`: SSR and Node standalone adapter configuration.
- `app/tsconfig.json`: Astro strict TypeScript defaults.
- `app/src/pages/index.astro`: minimal SSR status page that displays configured dependency endpoints without exposing secrets.
- `app/Dockerfile`: reproducible pnpm install and Astro SSR runtime stages.
- `app/.dockerignore`: excludes host dependencies and build output.
- `toolchain/Dockerfile`: latest stable Rust/Cargo plus Wasmtime.
- `workspace/.gitkeep`: mount target for toolchain projects.
- `compose.yaml`: service topology, health checks, environment, volumes, ports, and tool profile.
- `Caddyfile`: reverse proxy from Caddy to Astro.
- `.env.example`: documented local ports and credentials.
- `.gitignore`: ignores `.env`, dependencies, and generated output.
- `scripts/verify.sh`: static and live stack acceptance checks.
- `README.md`: setup, URLs, commands, configuration, persistence, and teardown.

---

### Task 1: Scaffold the pnpm Astro SSR application

**Files:**
- Create: `app/package.json`
- Create: `app/pnpm-lock.yaml`
- Create: `app/astro.config.mjs`
- Create: `app/tsconfig.json`
- Create: `app/src/pages/index.astro`

**Interfaces:**
- Consumes: environment variables `DATABASE_URL`, `S3_ENDPOINT`, and `S3_BUCKET`.
- Produces: an SSR server listening on port `4321`; production entry point `app/dist/server/entry.mjs`.

- [ ] **Step 1: Generate the official minimal scaffold with pnpm**

Run:

```bash
corepack enable
pnpm create astro@latest app --template minimal --install --no-git --yes
cd app
pnpm astro add node --yes
```

Expected: `app/package.json` declares the current `astro` and `@astrojs/node` releases and `app/pnpm-lock.yaml` exists.

- [ ] **Step 2: Add a failing build assertion for SSR configuration**

Run:

```bash
test -f app/dist/server/entry.mjs
```

Expected: FAIL because the scaffold has not yet been configured and built for standalone SSR.

- [ ] **Step 3: Configure Astro for standalone Node SSR**

Replace `app/astro.config.mjs` with:

```js
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
  server: { host: true, port: 4321 },
});
```

Replace `app/src/pages/index.astro` with:

```astro
---
const services = [
  { name: 'PostgreSQL', endpoint: import.meta.env.DATABASE_URL ? 'postgres:5432' : 'not configured' },
  { name: 'RustFS S3', endpoint: import.meta.env.S3_ENDPOINT ?? 'not configured' },
  { name: 'RustFS bucket', endpoint: import.meta.env.S3_BUCKET ?? 'not configured' },
];
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width" />
    <title>Astro Docker Stack</title>
  </head>
  <body>
    <main>
      <p>Astro SSR</p>
      <h1>The stack is running.</h1>
      <ul>{services.map(({ name, endpoint }) => <li><strong>{name}:</strong> {endpoint}</li>)}</ul>
    </main>
  </body>
</html>
```

- [ ] **Step 4: Build and verify the SSR entry point**

Run:

```bash
cd app
pnpm build
test -f dist/server/entry.mjs
```

Expected: Astro reports a successful server build and the file assertion exits 0.

- [ ] **Step 5: Commit the scaffold**

```bash
git add app
git commit -m "feat: scaffold pnpm Astro SSR app"
```

### Task 2: Containerize Astro and the Rust/Wasmtime toolchain

**Files:**
- Create: `app/Dockerfile`
- Create: `app/.dockerignore`
- Create: `toolchain/Dockerfile`
- Create: `workspace/.gitkeep`

**Interfaces:**
- Consumes: Astro files from Task 1 and build arguments `PNPM_VERSION` and `WASMTIME_VERSION`.
- Produces: `astro` image command `node ./dist/server/entry.mjs`; `toolchain` image with `rustc`, `cargo`, and `wasmtime` on `PATH`.

- [ ] **Step 1: Add failing image checks**

Run:

```bash
docker build -t docker-caddy-astro:test app
docker build -t docker-caddy-toolchain:test toolchain
```

Expected: FAIL because neither Dockerfile exists.

- [ ] **Step 2: Add the multi-stage Astro Dockerfile**

Create `app/Dockerfile`:

```dockerfile
FROM node:24-bookworm-slim AS base
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable
WORKDIR /app

FROM base AS dependencies
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

FROM dependencies AS build
COPY . .
RUN pnpm build

FROM base AS runtime
ENV HOST=0.0.0.0
ENV PORT=4321
ENV NODE_ENV=production
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
EXPOSE 4321
CMD ["node", "./dist/server/entry.mjs"]
```

Create `app/.dockerignore`:

```text
node_modules
dist
.astro
.git
```

- [ ] **Step 3: Add the isolated toolchain Dockerfile**

Create `toolchain/Dockerfile`:

```dockerfile
FROM rust:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl https://wasmtime.dev/install.sh -sSf | bash

ENV PATH=/root/.wasmtime/bin:/usr/local/cargo/bin:$PATH
WORKDIR /workspace
CMD ["bash"]
```

Create the empty tracked mount directory as `workspace/.gitkeep`.

- [ ] **Step 4: Build and inspect both images**

Run:

```bash
docker build -t docker-caddy-astro:test app
docker build -t docker-caddy-toolchain:test toolchain
docker run --rm docker-caddy-toolchain:test sh -ec 'rustc --version && cargo --version && wasmtime --version'
```

Expected: both builds succeed and all three version commands print version strings.

- [ ] **Step 5: Commit container definitions**

```bash
git add app/Dockerfile app/.dockerignore toolchain/Dockerfile workspace/.gitkeep
git commit -m "build: containerize Astro and Rust toolchain"
```

### Task 3: Compose the backing services and Caddy proxy

**Files:**
- Create: `compose.yaml`
- Create: `Caddyfile`
- Create: `.env.example`
- Create: `.gitignore`

**Interfaces:**
- Consumes: image contexts `app/` and `toolchain/`, plus variables from `.env`.
- Produces: public Astro URL `http://localhost:${HTTP_PORT}`, RustFS S3 URL `http://localhost:${RUSTFS_API_PORT}`, RustFS console URL `http://localhost:${RUSTFS_CONSOLE_PORT}`, and profile service `toolchain`.

- [ ] **Step 1: Add the environment contract**

Create `.env.example`:

```dotenv
HTTP_PORT=8080
POSTGRES_DB=app
POSTGRES_USER=app
POSTGRES_PASSWORD=local-development-password
RUSTFS_API_PORT=9000
RUSTFS_CONSOLE_PORT=9001
RUSTFS_ACCESS_KEY=rustfsadmin
RUSTFS_SECRET_KEY=rustfsadmin
S3_BUCKET=app
```

Create `.gitignore`:

```text
.env
app/node_modules/
app/dist/
app/.astro/
workspace/target/
```

- [ ] **Step 2: Add a failing Compose validation**

Run:

```bash
cp .env.example .env
docker compose config --quiet
```

Expected: FAIL because `compose.yaml` does not exist.

- [ ] **Step 3: Define the five-service topology**

Create `compose.yaml`:

```yaml
name: docker-caddy-astro

services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "${HTTP_PORT:-8080}:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      astro:
        condition: service_healthy
    restart: unless-stopped

  astro:
    build: ./app
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER:-app}:${POSTGRES_PASSWORD:-local-development-password}@postgres:5432/${POSTGRES_DB:-app}
      S3_ENDPOINT: http://rustfs:9000
      S3_ACCESS_KEY: ${RUSTFS_ACCESS_KEY:-rustfsadmin}
      S3_SECRET_KEY: ${RUSTFS_SECRET_KEY:-rustfsadmin}
      S3_BUCKET: ${S3_BUCKET:-app}
    depends_on:
      postgres:
        condition: service_healthy
      rustfs:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:4321/').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]
      interval: 5s
      timeout: 3s
      retries: 12
      start_period: 10s
    restart: unless-stopped

  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-app}
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-local-development-password}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 12
    restart: unless-stopped

  rustfs:
    image: rustfs/rustfs:latest
    environment:
      RUSTFS_VOLUMES: /data
      RUSTFS_ADDRESS: 0.0.0.0:9000
      RUSTFS_CONSOLE_ADDRESS: 0.0.0.0:9001
      RUSTFS_CONSOLE_ENABLE: "true"
      RUSTFS_ACCESS_KEY: ${RUSTFS_ACCESS_KEY:-rustfsadmin}
      RUSTFS_SECRET_KEY: ${RUSTFS_SECRET_KEY:-rustfsadmin}
    ports:
      - "${RUSTFS_API_PORT:-9000}:9000"
      - "${RUSTFS_CONSOLE_PORT:-9001}:9001"
    volumes:
      - rustfs_data:/data
    healthcheck:
      test: ["CMD", "sh", "-ec", "curl -fsS http://127.0.0.1:9000/health && curl -fsS http://127.0.0.1:9001/rustfs/console/health"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 20s
    restart: unless-stopped

  toolchain:
    profiles: [tools]
    build: ./toolchain
    volumes:
      - ./workspace:/workspace
      - cargo_registry:/usr/local/cargo/registry
      - cargo_git:/usr/local/cargo/git
    stdin_open: true
    tty: true

volumes:
  caddy_data:
  caddy_config:
  postgres_data:
  rustfs_data:
  cargo_registry:
  cargo_git:
```

- [ ] **Step 4: Configure Caddy**

Create `Caddyfile`:

```caddyfile
{
	auto_https off
	admin off
}

:80 {
	encode zstd gzip
	reverse_proxy astro:4321
}
```

- [ ] **Step 5: Validate configuration and service expansion**

Run:

```bash
docker compose config --quiet
docker compose --profile tools config --services
```

Expected: validation exits 0; service output contains `caddy`, `astro`, `postgres`, `rustfs`, and `toolchain`.

- [ ] **Step 6: Commit the stack configuration**

```bash
git add compose.yaml Caddyfile .env.example .gitignore
git commit -m "feat: compose Caddy PostgreSQL and RustFS stack"
```

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
