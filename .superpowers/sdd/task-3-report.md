# Task 3 report: Compose backing services and Caddy proxy

Status: DONE_WITH_CONCERNS

## Changed files

- `compose.yaml` — defines the Caddy, Astro, PostgreSQL, RustFS, and opt-in
  `toolchain` services; persistent volumes; health-gated dependencies; port and
  credential interpolation.
- `Caddyfile` — disables automatic HTTPS/admin and proxies HTTP traffic to
  `astro:4321` with zstd/gzip compression.
- `.env.example` — documents all host-port, PostgreSQL, RustFS, and S3 bucket
  variables with local-development defaults.
- `.gitignore` — ignores local configuration and generated app/toolchain output.

`cp .env.example .env` was run for Compose interpolation validation. The local
`.env` is ignored and is not a requested tracked file.

## Validation

1. Red validation before `compose.yaml` existed:

   ```sh
   cp .env.example .env
   docker compose config --quiet
   ```

   Result: failed as expected, but because this installation has no `docker
   compose` subcommand (`unknown flag: --quiet`) rather than because the compose
   file was absent.

2. Final standalone Compose validation:

   ```sh
   docker-compose config --quiet
   docker-compose --profile tools config --services
   ```

   Result: both exited 0. The service expansion listed `postgres`, `rustfs`,
   `toolchain`, `astro`, and `caddy`.

3. Static YAML/topology assertions:

   ```sh
   ruby -ryaml -e 'document = YAML.load_file("compose.yaml"); abort "missing expected services" unless document.fetch("services").keys.sort == %w[astro caddy postgres rustfs toolchain]; abort "invalid Postgres escaping" unless document.dig("services", "postgres", "healthcheck", "test", 1).include?("$${POSTGRES_USER}"); abort "tools profile missing" unless document.dig("services", "toolchain", "profiles") == ["tools"]; abort "RustFS healthcheck missing console endpoint" unless document.dig("services", "rustfs", "healthcheck", "test", 3).include?("/rustfs/console/health"); puts "YAML topology assertions passed"'
   ```

   Result: exited 0; printed `YAML topology assertions passed`.

4. Interpolation assertions against Compose's rendered configuration:

   ```sh
   docker-compose config > /private/tmp/docker-caddy-compose-expanded.yaml
   ruby -ryaml -e 'document = YAML.load_file("/private/tmp/docker-caddy-compose-expanded.yaml"); abort "interpolated Astro database URL is incorrect" unless document.dig("services", "astro", "environment", "DATABASE_URL") == "postgresql://app:local-development-password@postgres:5432/app"; abort "escaped Postgres healthcheck was not preserved" unless document.dig("services", "postgres", "healthcheck", "test", 1).include?("${POSTGRES_USER}"); puts "Compose interpolation assertions passed"'
   ```

   Result: both exited 0; printed `Compose interpolation assertions passed`.

5. Final self-review assertions:

   ```sh
   docker-compose config --quiet
   docker-compose --profile tools config --services | sort > /private/tmp/docker-caddy-services.txt
   ruby -ryaml -e 'document = YAML.load_file("compose.yaml"); abort "unexpected services" unless document.fetch("services").keys.sort == %w[astro caddy postgres rustfs toolchain]; abort "Postgres healthcheck variables are not escaped" unless document.dig("services", "postgres", "healthcheck", "test", 1).include?("$${POSTGRES_USER}"); abort "Astro must wait for healthy services" unless document.dig("services", "astro", "depends_on").values.all? { |dependency| dependency["condition"] == "service_healthy" }; abort "RustFS healthcheck does not cover API and console" unless document.dig("services", "rustfs", "healthcheck", "test", 3).include?("http://127.0.0.1:9000/health") && document.dig("services", "rustfs", "healthcheck", "test", 3).include?("http://127.0.0.1:9001/rustfs/console/health"); caddyfile = File.read("Caddyfile"); abort "Caddyfile proxy contract is incomplete" unless caddyfile.include?("auto_https off") && caddyfile.include?("admin off") && caddyfile.include?("encode zstd gzip") && caddyfile.include?("reverse_proxy astro:4321"); puts "Compose and Caddy static assertions passed"'
   ruby -e 'expected = %w[astro caddy postgres rustfs toolchain]; actual = File.readlines("/private/tmp/docker-caddy-services.txt", chomp: true); abort "service expansion mismatch: #{actual.inspect}" unless actual == expected; puts "Profile service expansion assertions passed"'
   ```

   Result: all commands exited 0; printed `Compose and Caddy static assertions
   passed` and `Profile service expansion assertions passed`.

## Concerns

- `docker compose` is unavailable in this Docker CLI. The installed standalone
  `docker-compose` parser was used instead.
- The Docker daemon has known `/var/lib/docker` I/O errors, so no containers,
  image pulls, or Caddy runtime validation were attempted.
- The local `caddy` executable is unavailable, so `caddy validate --config
  Caddyfile --adapter caddyfile` could not be run. The Caddyfile was reviewed
  statically and is mounted at Caddy's default configuration path.

## Review-fix follow-up

Status: DONE_WITH_CONCERNS

- Updated the PostgreSQL 18 volume target from the legacy
  `/var/lib/postgresql/data` path to `/var/lib/postgresql`.
- Added the one-shot `rustfs-permissions` service, using `alpine:3.21` as root
  (`0:0`) to run `chown -R 10001:10001 /rustfs-data` on the `rustfs_data`
  volume. It has `restart: "no"`.
- Added a `service_completed_successfully` dependency from `rustfs` to
  `rustfs-permissions`. Astro continues to wait on RustFS with
  `condition: service_healthy`.

### Follow-up validation

```sh
docker-compose config --quiet
docker-compose --profile tools config --services | sort
```

Result: both exited 0. The profile expansion listed:

```text
astro
caddy
postgres
rustfs
rustfs-permissions
toolchain
```

```sh
ruby -ryaml -e 'document = YAML.load_file("compose.yaml"); services = document.fetch("services"); abort "unexpected services: #{services.keys.sort.inspect}" unless services.keys.sort == %w[astro caddy postgres rustfs rustfs-permissions toolchain]; abort "Postgres 18 data-root mount is incorrect" unless services.dig("postgres", "volumes") == ["postgres_data:/var/lib/postgresql"]; initializer = services.fetch("rustfs-permissions"); abort "initializer must run as root" unless initializer["user"] == "0:0"; abort "initializer data mount is incorrect" unless initializer["volumes"] == ["rustfs_data:/rustfs-data"]; abort "initializer chown command is incorrect" unless initializer["command"] == ["sh", "-ec", "chown -R 10001:10001 /rustfs-data"]; abort "initializer restart policy is incorrect" unless initializer["restart"] == "no"; abort "RustFS must wait for permissions initialization" unless services.dig("rustfs", "depends_on", "rustfs-permissions", "condition") == "service_completed_successfully"; abort "Astro must retain RustFS health dependency" unless services.dig("astro", "depends_on", "rustfs", "condition") == "service_healthy"; puts "Compose topology assertions passed"'
```

Result: exited 0; printed `Compose topology assertions passed`.

```sh
docker-compose config > /private/tmp/docker-caddy-compose-task3-fix-expanded.yaml
ruby -ryaml -e 'document = YAML.load_file("/private/tmp/docker-caddy-compose-task3-fix-expanded.yaml"); abort "rendered Postgres volume is incorrect" unless document.dig("services", "postgres", "volumes", 0, "source") == "postgres_data" && document.dig("services", "postgres", "volumes", 0, "target") == "/var/lib/postgresql"; abort "rendered permissions initializer is incorrect" unless document.dig("services", "rustfs-permissions", "user") == "0:0" && document.dig("services", "rustfs-permissions", "restart") == "no" && document.dig("services", "rustfs-permissions", "command") == ["sh", "-ec", "chown -R 10001:10001 /rustfs-data"]; abort "rendered RustFS dependency is incorrect" unless document.dig("services", "rustfs", "depends_on", "rustfs-permissions", "condition") == "service_completed_successfully"; puts "Rendered Compose assertions passed"'
```

Result: both commands exited 0; printed `Rendered Compose assertions passed`.

No containers or image pulls were attempted because of the existing unhealthy
Docker daemon concern documented above.
