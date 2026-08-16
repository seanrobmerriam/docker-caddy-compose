# Docker Caddy Astro Stack Design

## Goal

Provide a local development stack that starts from a fresh clone with `docker compose up --build`. The stack serves a minimal Astro SSR application through Caddy and supplies PostgreSQL, S3-compatible object storage through RustFS, and an isolated Rust/Cargo/Wasmtime development environment.

## Architecture

The Compose project contains five services on one private network:

- `caddy` is the only public web entry point. It listens on the configured HTTP port and reverse-proxies requests to the Astro service. Its data and configuration state use named volumes.
- `astro` runs a minimal Astro project in SSR mode with the official Node adapter. Dependencies are managed with pnpm. Its container receives database and object-store connection settings through environment variables.
- `postgres` provides the application database, persists data in a named volume, and exposes a health check that dependent services can use.
- `rustfs` runs the official RustFS image in single-node, single-disk mode. Its S3 API and management console are published for local development, and object data persists in a named volume.
- `toolchain` is a separate, on-demand development container based on the official latest stable Rust image. It includes Cargo and Wasmtime and mounts a repository `workspace/` directory. It does not run as part of the normal web request path.

Requests flow from the browser to Caddy and then to Astro. Astro connects directly to PostgreSQL and RustFS over the private Compose network. The tooling container shares the network and can access those services when invoked manually.

## Repository Layout

- `compose.yaml` defines services, health checks, dependencies, networks, volumes, and environment interpolation.
- `Caddyfile` defines the local reverse proxy.
- `app/` contains the minimal Astro SSR scaffold, its pnpm lockfile, and a multi-stage Dockerfile.
- `toolchain/` contains the Rust/Wasmtime Dockerfile.
- `workspace/` is mounted into the tooling container for Rust and WebAssembly projects.
- `.env.example` documents configurable ports and local credentials.
- `README.md` documents setup, service URLs, common commands, and credential handling.

## Runtime and Configuration

The Astro image uses pnpm through Corepack. Its development command listens on all container interfaces so Caddy can reach it. The Dockerfile uses multiple stages to keep dependency installation reproducible while retaining a development-friendly runtime.

PostgreSQL and RustFS receive non-secret local defaults from `.env.example`. Compose uses service DNS names (`postgres` and `rustfs`) in application-facing connection strings. Users copy `.env.example` to `.env` before startup; `.env` is ignored by Git.

The toolchain image tracks the official `rust:latest` tag, which supplies the latest stable Rust compiler and Cargo at image-build time. Wasmtime is installed from its official installer and placed on `PATH`. The service is assigned to a `tools` Compose profile so it does not start with the main stack; users invoke it explicitly with `docker compose run --rm toolchain`.

## Startup and Failure Behavior

PostgreSQL and RustFS have health checks. Astro waits for required backing services to become healthy before startup. Caddy starts after Astro is available. Containers use restart policies appropriate for local development without hiding persistent configuration errors.

Persistent state lives only in named volumes. Rebuilding application or tooling images does not delete database or object data. The README explicitly documents the destructive command for removing volumes.

## Verification

Implementation is complete when:

1. The Astro project installs and builds successfully with pnpm.
2. `docker compose config` validates with the documented environment file.
3. All custom Docker images build successfully.
4. `docker compose up --build` makes the Astro page reachable through Caddy.
5. PostgreSQL reports healthy and retains data across container recreation.
6. RustFS exposes its S3 API and console and retains objects across container recreation.
7. `docker compose run --rm toolchain rustc --version`, `cargo --version`, and `wasmtime --version` all succeed.

## Scope Boundaries

This stack is intended for local development. It does not include production TLS, external secret management, database migrations, pre-created S3 buckets, application authentication, observability services, or a production deployment topology.
