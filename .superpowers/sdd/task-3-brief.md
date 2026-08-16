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

