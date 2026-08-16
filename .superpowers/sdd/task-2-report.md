# Task 2 report: Astro and Rust/Wasmtime containers

## Files changed

- `app/Dockerfile` — specified four-stage Astro SSR image; production command is `node ./dist/server/entry.mjs` and port 4321 is exposed.
- `app/.dockerignore` — excludes `node_modules`, `dist`, `.astro`, and `.git` from the build context.
- `toolchain/Dockerfile` — Rust base image with certificates, curl, Wasmtime installer, PATH, `/workspace` workdir, and `bash` default command.
- `workspace/.gitkeep` — tracks the empty intended mount directory.

No commit was created because the parent task explicitly states that the actual parent git root is read-only and commits must not be attempted.

## Commands and results

### Required pre-implementation checks

```text
$ docker build -t docker-caddy-astro:test app
unable to prepare context: ... app/Dockerfile: no such file or directory
```

```text
$ docker build -t docker-caddy-toolchain:test toolchain
unable to prepare context: path "toolchain" not found
```

Both checks failed as expected before the container files were added.

### Required post-implementation checks

```text
$ docker build -t docker-caddy-astro:test app
...
ERR_PNPM_IGNORED_BUILDS Ignored build scripts: esbuild@0.28.2
The command '/bin/sh -c pnpm install --frozen-lockfile' returned a non-zero code: 1
```

The Astro image does not build in its current dependency configuration. The failure occurs in the specified `RUN pnpm install --frozen-lockfile` line: Node 24's Corepack downloads pnpm 11.22.0, which enforces build-script approval and rejects `esbuild` as unapproved.

```text
$ docker build -t docker-caddy-toolchain:test toolchain
Successfully built 4aa92c7b6d49d647265d6b71a667280907dbd803433557a495f251b895c89ed6
Successfully tagged docker-caddy-toolchain:test
```

```text
$ docker run --rm docker-caddy-toolchain:test sh -ec 'rustc --version && cargo --version && wasmtime --version'
rustc 1.97.1 (8bab26f4f 2026-07-14)
cargo 1.97.1 (c980f4866 2026-06-30)
wasmtime 47.0.3 (5554cc1a6 2026-07-31)
```

### Additional validation

```text
$ docker image inspect docker-caddy-toolchain:test --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}} Workdir={{.Config.WorkingDir}}'
Entrypoint=null Cmd=["bash"] Workdir=/workspace
```

```text
$ cd app && pnpm build
ERR_UNKNOWN_BUILTIN_MODULE: No such built-in module: node:sqlite
Node.js v20.20.2
```

The local host build is not a container regression check: the host supplies Node 20.20.2, while this app requires Node >=22.12.0 and the container correctly uses Node 24.

## Self-review

- Dockerfile stage names, base image, environment variables, copied runtime artifacts, exposed port, and SSR entry command match the task brief exactly.
- `.dockerignore` contains exactly the requested paths, keeping generated output and host dependencies out of the image context.
- Toolchain PATH was exercised by running all required executables in the built image.
- No unrelated project files were changed.

## Task 2 fix

### Changed files

- `app/package.json` — declares the exact project package manager as `pnpm@10.12.4`. Corepack in the existing `app/Dockerfile` now honors this declaration, so the image no longer selects pnpm 11.

### Commands and results

```text
$ docker build -t docker-caddy-astro:test app
...
Ignored build scripts: esbuild.
...
Done in 1.9s using pnpm v10.12.4
...
Server built in 348ms
...
Successfully built c38eb8959858
Successfully tagged docker-caddy-astro:test
```

The build passed with `--frozen-lockfile` unchanged. pnpm 10 retained its build-script security policy and emitted a warning about the unapproved esbuild script; it did not fail the install and no approval or policy bypass was added.

```text
$ container_id=$(docker run -d -p 4321:4321 docker-caddy-astro:test)
$ curl --fail --silent --show-error http://127.0.0.1:4321/
container=7846bfc5968c4614ffebb9c9a42eb88a690dc46fb377e22f28636f56f67bf464
response-prefix=<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width"><title>Astro Docker Stack</title></head><body><mai
```

The container answered successfully on port 4321 and was removed by the smoke-check cleanup trap.

## Concerns

1. The required Astro image success check is blocked by pnpm 11's build-script approval policy. Resolving it requires a scope decision outside the exact requested Dockerfile: pin/declare a compatible pnpm version (the stated interface mentions `PNPM_VERSION`, but the supplied Dockerfile does not declare it), or allow `esbuild` as a build dependency in the pnpm workspace configuration.
2. Both `node:24-bookworm-slim` and `rust:latest`, plus the Wasmtime installer, are intentionally unpinned as mandated. Rebuilds can therefore change behavior and installed versions over time.

## Task 2 configurable build-argument fix

### Changed files

- `app/Dockerfile` — adds `ARG PNPM_VERSION=10.12.4` and uses Corepack's `corepack install --global pnpm@${PNPM_VERSION}` after enabling Corepack.
- `toolchain/Dockerfile` — adds `ARG WASMTIME_VERSION=47.0.3` and passes the official installer's supported `--version` option as `v${WASMTIME_VERSION}`.

`app/package.json` already declares `packageManager: "pnpm@10.12.4"`, so the default Docker build argument and package-manager pin remain consistent.

### Commands and results

```text
$ curl -fsSL https://wasmtime.dev/install.sh | ...
USAGE: wasmtime-install [FLAGS] [OPTIONS]
        --version <version>     Install a specific release version of Wasmtime
```

The official installer source confirms that release tags are passed as the `v`-prefixed version (for example, `v47.0.3`).

```text
$ docker build -t docker-caddy-astro:test app
...
Done in 2s using pnpm v10.12.4
...
Server built in 436ms
...
commit failed: write /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/metadata.db: input/output error
```

The Astro dependency install and production build passed with the default `PNPM_VERSION`, but Docker could not commit the final image layer because its storage backend returned an I/O error.

```text
$ docker build -t docker-caddy-toolchain:test toolchain
Error response from daemon: mkdir /var/lib/docker/tmp/docker-builder2950578099: input/output error
```

```text
$ docker run --rm docker-caddy-astro:test sh -ec 'pnpm --version'
Error response from daemon: ... blob ... input/output error
```

The Docker daemon's filesystem reported only 119 MiB available and 100% capacity. `docker builder prune -af` reclaimed 0 B. After removing only task-specific temporary caches, 224 MiB became available, but the daemon's blob/metadata I/O errors remained. The Astro HTTP smoke check and toolchain version checks could not be rerun in this environment after the storage failure. No commit was created.

## Verification status

DONE_WITH_CONCERNS — Dockerfile changes are implemented and the Astro build reached completion using pnpm 10.12.4, but final image creation and all post-build container checks are blocked by the Docker daemon's storage backend. Re-run both builds, the Astro HTTP check, and `rustc --version && cargo --version && wasmtime --version` after Docker storage is repaired.

## Task 2 follow-up: project-selected pnpm build-arg fix

### Exact change

- `app/Dockerfile` — in the `dependencies` stage, explicitly declares `ARG PNPM_VERSION=10.12.4`, then runs `corepack use pnpm@${PNPM_VERSION}` immediately after copying `package.json` and `pnpm-lock.yaml`, before `pnpm install --frozen-lockfile`. This makes a `PNPM_VERSION` build-arg override update the project-selected package manager in the copied manifest. The default remains consistent with `app/package.json`'s `packageManager: "pnpm@10.12.4"`.

### Static inspection and build tests

```text
$ rg -n -U 'FROM base AS dependencies\\nARG PNPM_VERSION=10\\.12\\.4\\nCOPY package\\.json pnpm-lock\\.yaml \\.\\/\\nRUN corepack use pnpm@\\$\\{PNPM_VERSION\\} \\\\\n    && pnpm install --frozen-lockfile' app/Dockerfile
9:FROM base AS dependencies
10:ARG PNPM_VERSION=10.12.4
11:COPY package.json pnpm-lock.yaml ./
12:RUN corepack use pnpm@${PNPM_VERSION} \\
13:    && pnpm install --frozen-lockfile
```

`docker info` reached Docker Server 29.2.1, but the daemon storage backend remains unavailable for builds:

```text
$ docker build -t docker-caddy-astro:task2-pnpm-default app
Error response from daemon: mkdir /var/lib/docker/tmp/docker-builder4032673363: input/output error

$ docker build --build-arg PNPM_VERSION=10.12.5 -t docker-caddy-astro:task2-pnpm-alt app
Error response from daemon: mkdir /var/lib/docker/tmp/docker-builder2343880548: input/output error
```

Neither build reached the Dockerfile steps, so no pnpm version output could be captured. No Docker cleanup or destructive operation was performed.
