# Final review fix report

Date: 2026-08-15
Status: **DONE_WITH_CONCERNS**

All requested source, configuration, test, ignore, and documentation fixes are implemented. The remaining concerns are environmental: this host has no callable `docker compose` v2 plugin, and both safe Docker image-build attempts stop in the daemon's `/var/lib/docker/tmp` with an input/output error. No image/runtime or full live-stack success is claimed.

## Changes applied

- `app/Dockerfile`
  - Replaced mutating `corepack use`/global selection with `corepack pnpm@${PNPM_VERSION}` for both the frozen install and build.
  - Copies `pnpm-workspace.yaml` before dependency installation.
  - Retains the configurable `PNPM_VERSION=10.12.4` default.
  - Gives `/app` and all copied runtime artifacts to the built-in `node` account, then runs with `USER node`.
- `app/pnpm-workspace.yaml`
  - Replaced unsupported `allowBuilds` with pnpm-10.12.4-supported `onlyBuiltDependencies` for `esbuild` and `sharp`.
- `compose.yaml`
  - Binds all three published Caddy/RustFS ports through `${BIND_ADDRESS:-127.0.0.1}`.
  - Passes `${DATABASE_URL:-postgresql://app:local-development-password@postgres:5432/app}` directly to Astro.
  - Passes configurable `PNPM_VERSION` and `WASMTIME_VERSION` build arguments with defaults `10.12.4` and `47.0.3`.
  - Adds connection and total timeouts to both RustFS curl health probes.
  - Preserves the approved `rustfs-permissions` initializer and PostgreSQL 18 data-root mount.
- `.env.example`
  - Adds `BIND_ADDRESS`, separate `DATABASE_URL`, `PNPM_VERSION`, and `WASMTIME_VERSION` defaults.
- `scripts/resolve-compose-value.sh`
  - Removes all custom dotenv parsing.
  - Requires Compose v2 and resolves from authoritative `docker compose config --environment` output.
  - Preserves `${VAR:-default}` behavior for empty/missing values and reports invalid names, missing v2, and Compose configuration failures clearly.
- `scripts/test-verify-env-precedence.sh`
  - Uses a mocked Compose-native environment output.
  - Covers caller overrides, empty/default values, quoted values, embedded spaces and `#`, comments, interpolation, missing variables, missing Compose v2, and Compose configuration failure.
  - Verifies that unrelated caller environment values reach later Docker commands unchanged.
- `scripts/verify.sh`
  - Uses the Compose-native resolver for the bind address and all probe ports.
  - Adds `--connect-timeout 5 --max-time 10` to all host curl probes.
- `README.md`
  - Keeps startup detached.
  - Documents loopback binding and the implications of `0.0.0.0`.
  - Documents build-version defaults and compatible pnpm override expectations.
  - Documents direct `DATABASE_URL` use and percent-encoding requirements when PostgreSQL settings change.
  - Passes resolved RustFS credentials and bucket explicitly as `-e NAME="$NAME"` in both persistence client runs.
  - Documents Compose v2 as the operational target and standalone `docker-compose` only as local static validation fallback.
- Ignore/documentation cleanup
  - Added `.pnpm-store/` and `workspace/**/target/` to the root `.gitignore`; no store/cache was deleted.
  - Added `.env*` with `!.env.example` to `app/.dockerignore`.
  - Replaced the generated Astro starter README with short standalone-SSR/container guidance.

## Red checks observed before fixes

1. A clean pnpm 10.12.4 install using the old `allowBuilds` policy completed with:

   ```text
   Ignored build scripts: esbuild.
   ```

2. Running the updated resolver/verification harness against the old implementation under `sh -x` stopped at the expected new curl contract comparison:

   ```text
   test '--fail --silent --show-error http://localhost:18180/' = '--fail --silent --show-error --connect-timeout 5 --max-time 10 http://127.0.0.1:18180/'
   ```

   The later resolver cases also require Compose-native dequoting/interpolation and missing-v2 errors, neither of which the old parser provided.

## Final verification evidence

### Shell, Task 4 harness, Compose fallback, and text checks

Exact commands:

```sh
sh -n scripts/resolve-compose-value.sh scripts/test-verify-env-precedence.sh scripts/verify.sh
test -x scripts/resolve-compose-value.sh
test -x scripts/test-verify-env-precedence.sh
test -x scripts/verify.sh
scripts/test-verify-env-precedence.sh
docker-compose config --quiet
COMPOSE_PROFILES=tools docker-compose --env-file .env.example config --quiet
awk 'BEGIN { fences = 0 } /^```/ { fences++ } END { if (fences % 2) exit 1; print "README fences balanced:", fences }' README.md
ruby -e 'ARGV.each { |path| File.read(path).scan(/```sh\n(.*?)```/m) { |match| puts match.first } }' README.md app/README.md | sh -n
rg -n '[[:blank:]]+$' .env.example .gitignore Caddyfile README.md app/.dockerignore app/Dockerfile app/README.md app/pnpm-workspace.yaml compose.yaml scripts toolchain/Dockerfile
```

Results:

- All `sh -n`, executable-bit, mock-harness, and both standalone Compose validation commands exited successfully.
- README shell snippets parsed successfully with `sh -n`.
- Fence check printed `README fences balanced: 12`.
- The trailing-whitespace search returned no matches.

The harness specifically asserted these Compose-native resolved values from quoted/commented/interpolated dotenv syntax:

```text
HTTP_PORT=18181
RUSTFS_API_PORT=19002
RUSTFS_CONSOLE_PORT=19003
QUOTED_VALUE=quoted value # literal
SPACED_VALUE=unquoted value with spaces
INTERPOLATED_VALUE=quoted value # literal-suffix
```

A separate local fallback parse used the exact command below and passed all six value assertions:

```sh
env -i PATH="$PATH" docker-compose -f compose.yaml --env-file "$fixture_root/.env" config --environment
```

### Clean pnpm 10.12.4 install and Astro SSR build

The final check copied only application source/manifests into a fresh temporary directory and used a fresh temporary pnpm store. Exact pnpm commands:

```sh
PATH=/Users/sean/.nvm/versions/node/v24.14.1/bin:$PATH COREPACK_HOME=/private/tmp/docker-caddy-corepack-final corepack pnpm@10.12.4 --version
PATH=/Users/sean/.nvm/versions/node/v24.14.1/bin:$PATH COREPACK_HOME=/private/tmp/docker-caddy-corepack-final corepack pnpm@10.12.4 install --frozen-lockfile --store-dir "$store_root" --reporter=append-only
PATH=/Users/sean/.nvm/versions/node/v24.14.1/bin:$PATH COREPACK_HOME=/private/tmp/docker-caddy-corepack-final corepack pnpm@10.12.4 build
test -f dist/server/entry.mjs
```

Results:

```text
10.12.4
Lockfile is up to date, resolution step is skipped
.../esbuild@0.28.2/node_modules/esbuild postinstall$ node install.js
.../esbuild@0.28.2/node_modules/esbuild postinstall: Done
Done ... using pnpm v10.12.4
[build] output: "server"
[build] mode: "server"
[build] adapter: @astrojs/node
[build] Server built
[build] Complete!
```

No `Ignored build scripts: esbuild` line was present. `dist/server/entry.mjs` existed. Starting that output with Node 24 on `127.0.0.1:14322` and probing it with curl succeeded; the response contained `The stack is running.` and `PostgreSQL:` and did not contain the supplied database password marker.

### Rendered/static contracts

The `.env.example` render was produced with:

```sh
COMPOSE_PROFILES=tools docker-compose --env-file .env.example config
```

Ruby/YAML assertions over that render passed and printed:

```text
rendered Compose topology, ports, database, build args, init, and timeout assertions passed
```

They verified:

- normal services plus profile-gated `toolchain` and `rustfs-permissions`;
- Caddy `127.0.0.1:8080 -> 80` and RustFS `127.0.0.1:9000/9001` bindings;
- Astro `PNPM_VERSION=10.12.4` and toolchain `WASMTIME_VERSION=47.0.3` build args;
- the direct default `DATABASE_URL`;
- the exact root initializer command/user/restart/dependency contract;
- RustFS curl connection/overall timeouts.

The override render used this exact prefix:

```sh
BIND_ADDRESS=0.0.0.0 HTTP_PORT=18080 DATABASE_URL='postgresql://encoded%40user:p%3Ass%23word@postgres:5432/custom%2Fdb' COMPOSE_PROFILES=tools docker-compose --env-file .env.example config
```

It passed assertions that the shell bind/port values won and the percent-encoded URL reached Astro byte-for-byte.

Raw-file assertions also passed for no `corepack use`, versioned install/build invocations, workspace policy copied before install, `onlyBuiltDependencies`/`esbuild`, all three `BIND_ADDRESS` port expressions, direct `DATABASE_URL`, non-root runtime ownership/user, both requested ignore patterns, detached startup, explicit persistence `-e NAME="$NAME"` arguments, encoding guidance, and build-version documentation.

### Environmental failures / intentionally unclaimed checks

Exact image build attempts:

```sh
docker build -t docker-caddy-astro:final-review app
docker build -t docker-caddy-toolchain:final-review toolchain
```

Both sent their small contexts, then failed before executing Dockerfile instructions:

```text
Error response from daemon: mkdir /var/lib/docker/tmp/docker-builder...: input/output error
```

`docker info --format 'server={{.ServerVersion}} driver={{.Driver}}'` did respond with `server=29.2.1 driver=overlayfs`, but the builder storage path remains broken.

Compose v2 check:

```sh
docker compose version
```

Result:

```text
docker: unknown command: docker compose
```

Real verifier attempt:

```sh
./scripts/verify.sh
```

Result: stopped before probes because the missing plugin caused Docker to reject `--profile`. The resolver itself was separately checked to return the clear message `Docker Compose v2 is required to resolve project environment values.`

Therefore the final Docker images, container user at runtime, live Caddy/RustFS/PostgreSQL stack, and persistence round trip were not runnable on this host and are not reported as passing. No containers were started, no named volumes or user caches/data were deleted, `.pnpm-store/` was left intact, and no commit was attempted because the parent Git metadata is read-only.

### Final hardening follow-up

Changes applied:

- `toolchain/Dockerfile`: replaces the Wasmtime `curl | bash` pipeline with `curl -fsSL` downloading to `/tmp/wasmtime-install.sh`, executes that script with `--version "v${WASMTIME_VERSION}"`, verifies `/root/.wasmtime/bin/wasmtime --version`, and removes the temporary installer in the same fail-closed `&&` chain. The `WASMTIME_VERSION=47.0.3` default and PATH are unchanged.
- `compose.yaml`: quotes `"$${POSTGRES_USER}"` and `"$${POSTGRES_DB}"` in the PostgreSQL `CMD-SHELL` healthcheck, preserving Compose's `$$` escaping so shell expansion supplies each as a single argument.

Verification run:

```sh
# Static Dockerfile and Compose source assertions, including no curl-to-shell pipeline.
rg -q '^ARG WASMTIME_VERSION=47\\.0\\.3$' toolchain/Dockerfile
rg -q '^ENV PATH=/root/\\.wasmtime/bin:/usr/local/cargo/bin:\\$PATH$' toolchain/Dockerfile
rg -q 'curl -fsSL https://wasmtime\\.dev/install\\.sh -o /tmp/wasmtime-install\\.sh' toolchain/Dockerfile
rg -q '&& bash /tmp/wasmtime-install\\.sh --version "v\\$\\{WASMTIME_VERSION\\}"' toolchain/Dockerfile
rg -q '&& /root/\\.wasmtime/bin/wasmtime --version' toolchain/Dockerfile
rg -q '&& rm /tmp/wasmtime-install\\.sh' toolchain/Dockerfile
! rg -q 'curl .*\\|.*bash' toolchain/Dockerfile
rg -Fq 'pg_isready -U "$$\u007bPOSTGRES_USER\u007d" -d "$$\u007bPOSTGRES_DB\u007d"' compose.yaml
docker-compose -f compose.yaml config --quiet
docker-compose -f compose.yaml config
```

Results: static assertions and `docker-compose config --quiet` passed. The rendered healthcheck is:

```text
pg_isready -U "$${POSTGRES_USER}" -d "$${POSTGRES_DB}"
```

The following shell behavior check also passed with values containing whitespace and glob characters; its four arguments were preserved exactly:

```sh
POSTGRES_USER='owner name *' POSTGRES_DB='database name [x]' sh -c '
  pg_isready() { printf "<%s>\\n" "$@"; }
  pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
' | diff -u - <(printf '%s\\n' '<-U>' '<owner name *>' '<-d>' '<database name [x]>')
```

`docker compose -f compose.yaml config --quiet` could not be run because this host still lacks the Compose v2 subcommand (`unknown shorthand flag: 'f'`); standalone `docker-compose` was used for the requested static validation. Docker daemon/image build checks remain intentionally unclaimed due to its existing storage I/O error; no daemon cleanup was performed.
