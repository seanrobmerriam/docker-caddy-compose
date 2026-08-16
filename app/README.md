# Astro standalone SSR app

This directory contains the Node 24 Astro application served behind Caddy. `astro.config.mjs` builds the official Node adapter in standalone SSR mode, producing `dist/server/entry.mjs`.

Use Node 22.12 or newer and the pinned pnpm release for local checks:

```sh
corepack pnpm@10.12.4 install --frozen-lockfile
corepack pnpm@10.12.4 build
node ./dist/server/entry.mjs
```

For development, run `pnpm astro dev --background`; manage it with `pnpm astro dev status`, `pnpm astro dev logs`, and `pnpm astro dev stop`.

The container build accepts `PNPM_VERSION` (default `10.12.4`), installs from the frozen lockfile, and runs approved dependency build scripts from `pnpm-workspace.yaml`. The runtime work directory and copied files belong to the unprivileged `node` user, which starts `node ./dist/server/entry.mjs` on port `4321`.

Astro consumes `DATABASE_URL`, `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `S3_BUCKET` from the container environment. The status page reports service endpoints without rendering credentials.
