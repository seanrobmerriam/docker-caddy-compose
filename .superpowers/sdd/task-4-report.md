# Task 4 report: acceptance verification and operator documentation

Status: **DONE_WITH_CONCERNS**

## Files changed

- `scripts/verify.sh` — executable POSIX acceptance verifier for Compose
  configuration, Astro/Caddy, RustFS API and console, PostgreSQL readiness,
  and the opt-in Rust/Cargo/Wasmtime toolchain.
- `README.md` — start, toolchain, verification, configuration, persistence,
  and reset instructions.

No commit was created, as directed. No existing tracked files were modified.

## Implementation notes

- The verifier resolves its own project directory, so it can be invoked from a
  normal shell outside the repository root.
- It loads `.env` only for the host-side probes, retaining explicitly exported
  shell port values over `.env`, which matches Docker Compose's precedence.
- Toolchain commands include `--profile tools`, both in the verifier and in
  the operator documentation.
- The persistence procedure derives the live PostgreSQL container's network
  rather than assuming a project-derived network name. It passes RustFS
  credentials into the temporary `minio/mc` container as environment variables
  and does not print credential values or document development secret values.

## Verification

### TDD red check before implementation

The following mocked command-path check was run before `scripts/verify.sh`
existed:

```sh
PATH="$test_root/bin:$PATH" HTTP_PORT=18180 RUSTFS_API_PORT=19000 RUSTFS_CONSOLE_PORT=19001 ./scripts/verify.sh
```

Result: failed as expected with `zsh: no such file or directory:
./scripts/verify.sh`, exit `127`.

### Mocked acceptance checks after implementation

Mock `docker` and `curl` commands were placed first in `PATH`; the verifier
completed and its captured calls were asserted exactly. The shell-port run
used:

```sh
VERIFY_LOG="$check_root/docker.log" VERIFY_CURL_LOG="$check_root/curl.log" PATH="$check_root/bin:$PATH" HTTP_PORT=18180 RUSTFS_API_PORT=19000 RUSTFS_CONSOLE_PORT=19001 ./scripts/verify.sh
```

Result: exit `0`; captured calls included:

```text
compose --profile tools config --quiet
compose exec -T postgres sh -ec pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
compose --profile tools run --rm toolchain sh -ec rustc --version && cargo --version && wasmtime --version
--fail --silent --show-error http://localhost:18180/
--fail --silent --show-error http://localhost:19000/health
--fail --silent --show-error http://localhost:19001/rustfs/console/health
All stack checks passed.
```

An isolated temporary project with this `.env` was also exercised:

```text
HTTP_PORT=18181
RUSTFS_API_PORT=19002
RUSTFS_CONSOLE_PORT=19003
```

Result: exit `0`; the three captured URLs were `18181`, `19002`, and `19003`.
A second run with `HTTP_PORT=18180`, `RUSTFS_API_PORT=19000`, and
`RUSTFS_CONSOLE_PORT=19001` in the calling environment captured those shell
values instead, confirming the intended `.env` and shell-precedence behavior.

### Static checks

```sh
sh -n scripts/verify.sh
test -x scripts/verify.sh
docker-compose config --quiet
git diff --check --no-index /dev/null scripts/verify.sh
git diff --check --no-index /dev/null README.md
```

Results:

- `sh -n` and executable-bit checks passed.
- `docker-compose config --quiet` exited `0` without starting or changing
  containers.
- Both no-index `git diff --check` invocations had the expected exit `1` for a
  new file and produced no whitespace-error output.

The following content review also passed:

```sh
rg -n '^# Caddy \+ Astro SSR development stack$|^## Start$|^## Toolchain$|^## Verify$|^## Configuration$|^## Stop and reset$' README.md
! rg -n 'local-development-password|rustfsadmin|docker-caddy-astro_default' README.md scripts/verify.sh
```

It confirmed all required README sections and that neither the documentation
nor verifier embeds the example credential values or an assumed Compose
network name.

### Real verifier attempt

```sh
./scripts/verify.sh
```

Result: failed before probes with exit `125`:

```text
unknown flag: --profile

Usage:  docker [OPTIONS] COMMAND [ARG...]
```

This host has Docker CLI `29.6.1`, but no `docker compose` plugin
(`docker compose version` reports `docker: unknown command: docker compose`).
The available `docker-compose` binary reports version `5.1.3`, but its
`--profile` invocation delegates to the Docker CLI and fails. It can still
parse the normal configuration with `docker-compose config --quiet`.

## Environmental limitations

- The required Compose v2 plugin is unavailable, so the real verifier cannot
  reach its HTTP probes or execute the profile-targeted toolchain command on
  this host.
- The Docker daemon is known to have `/var/lib/docker` I/O corruption from
  earlier tasks. Per the task instructions, no stack startup, image pull,
  volume reset, or destructive cleanup was attempted.
- Consequently, the required live-stack run and persistence sequence remain
  for an environment with a functioning Docker Compose v2 installation and
  healthy Docker storage.

## Self-review

- Verified `set -eu`, POSIX `sh` syntax, an executable shebang, and no secret
  values in the new script or README.
- Verified the root, API, and console probes use ports resolved from `.env` or
  explicit shell overrides.
- Verified the verifier and all documented toolchain commands explicitly
  activate the `tools` profile.
- Verified persistence documentation is independent of the literal Compose
  network name and checks data without deleting named volumes.

## Follow-up: review fixes

The Task 4 review identified that the original verifier sourced `.env` with
`set -a`. Although it restored the three probe ports, that approach exported
every `.env` value and could overwrite caller configuration (for example,
`POSTGRES_USER`) for subsequent Compose commands.

### Exact changes

- `scripts/verify.sh` now uses a POSIX `env_default` helper which reads only
  an exact, simple `KEY=value` line from `.env`, strips one optional trailing
  carriage return, and returns the supplied fallback when no entry exists.
  It does not source `.env`, use `eval`, export values, or otherwise alter the
  inherited process environment. Explicit non-empty shell values for
  `HTTP_PORT`, `RUSTFS_API_PORT`, and `RUSTFS_CONSOLE_PORT` still take
  precedence.
- Added `scripts/test-verify-env-precedence.sh`, a mocked regression harness.
  It records the environment seen by every mocked `docker` invocation and the
  probe URLs seen by mocked `curl`.
- `README.md` now accurately states that the verifier reads only the three
  probe-port values and does not source `.env`. Its persistence recipe no
  longer sources `.env` or changes the operator shell: PostgreSQL credentials
  are read inside the Compose service, and the temporary `minio/mc` container
  receives RustFS values with `docker run --env-file .env`.
- The documented startup command remains `docker compose up --build -d`, as
  selected for this task; the persistence restart command remains detached
  (`docker compose up -d`).

### Follow-up verification

```sh
sh -n scripts/verify.sh
sh -n scripts/test-verify-env-precedence.sh
scripts/test-verify-env-precedence.sh
awk 'BEGIN { fences = 0 } /^```/ { fences++ } END { exit fences % 2 }' README.md
! rg -n '^[[:space:]]*\.[[:space:]]+\.?/\.env|set -a|set \+a' README.md
docker-compose config --quiet
git diff --check
```

All commands exited `0`. The mocked harness verified two cases: (1) shell
ports `18180`, `19000`, and `19001` won over `.env`, while the mocked Compose
calls retained `POSTGRES_USER=caller-user` and
`COMPOSE_PROJECT_NAME=caller-project`; (2) without those port variables, the
three probe URLs used `.env` values `18181`, `19002`, and `19003`.

No containers were started and no cleanup or volume deletion was performed.

## Follow-up: environment-resolution hardening

Status: **DONE**

### Exact changes

- Added `scripts/resolve-compose-value.sh`, an executable POSIX helper for the
  documented simple `KEY=value` `.env` format. It keeps every working variable
  inside a subshell with deliberately specific names, never sources or evaluates
  `.env`, strips a trailing carriage return, and leaves the caller environment
  unchanged.
- The helper mirrors `${VAR:-default}` exactly: a non-empty inherited value
  wins; an explicitly empty inherited value selects the hard default; only an
  absent inherited value consults the exact key in the project `.env`; absent or
  empty file values select the hard default.
- Refactored `scripts/verify.sh` to invoke the helper for all three host probe
  ports. The verifier no longer assigns ordinary internal variable names, so
  exported caller variables remain unmodified for each Compose invocation.
- Updated the persistence commands in `README.md` to resolve
  `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`, and `S3_BUCKET` through the helper.
  Each `docker run` receives only those variables through explicit `-e NAME`
  forwarding; neither `.env` loading syntax nor `--env-file` is documented.
- Expanded `scripts/test-verify-env-precedence.sh` with mocked Docker and curl
  coverage for non-empty shell override, explicit-empty shell values with a
  custom `.env`, absent shell values using `.env`, and an empty `.env` using the
  hard default. It also asserts that `POSTGRES_USER`, `COMPOSE_PROJECT_NAME`,
  and exported generic names (`key` and `line`) retain their caller values in
  Docker calls.

### Verification

```sh
sh -n scripts/resolve-compose-value.sh scripts/verify.sh scripts/test-verify-env-precedence.sh
scripts/test-verify-env-precedence.sh
awk 'BEGIN { fences = 0 } /^```/ { fences++ } END { exit fences % 2 }' README.md
! rg -n -- '--env-file|(^|[[:space:]])(source|\.)[[:space:]]+\.env' README.md
git diff --check
docker-compose config --quiet
```

All commands exited `0`. No containers were started and no commit was created.

## Follow-up: final review fixes

### Exact changes

- Updated the README persistence recipe to resolve `RUSTFS_ACCESS_KEY` and
  `RUSTFS_SECRET_KEY` with empty fallbacks instead of embedding development
  credentials. Each persistence pass now checks both resolved values and
  exits with a clear message directing the operator to `.env` when either is
  absent; the non-secret `S3_BUCKET` fallback remains `app`.
- Added a real CRLF resolver regression case to
  `scripts/test-verify-env-precedence.sh`; it writes `HTTP_PORT=19181` with a
  trailing carriage return and asserts the resolver returns `19181`.
- Added a resolver safety case that writes shell-substitution and semicolon
  text to `.env`, asserts the exact text is returned literally, and asserts a
  harmless sentinel file is not created.

### Verification

```sh
sh -n scripts/resolve-compose-value.sh scripts/verify.sh scripts/test-verify-env-precedence.sh
scripts/test-verify-env-precedence.sh
awk 'BEGIN { fences = 0 } /^```/ { fences++ } END { exit fences % 2 }' README.md
! rg -n 'rustfsadmin' README.md
! rg -n -- '--env-file|(^|[[:space:]])(source|\.)[[:space:]]+\.env' README.md
git diff --check
docker-compose config --quiet
```

All commands exited `0`. No containers were started and no commit was
created.
