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

