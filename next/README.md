# Recover Works Next.js service

This directory contains the Next.js 16 service served at `next.recover.works`. It is pinned to pnpm 10.12.4 and builds with Webpack into Next.js standalone output for the repository's Docker runtime.

## Local verification

Use the pinned pnpm version for dependency installation and every project command:

```sh
corepack pnpm@10.12.4 install --frozen-lockfile
corepack pnpm@10.12.4 lint
corepack pnpm@10.12.4 exec tsc --noEmit
corepack pnpm@10.12.4 build
```

The `build` script intentionally runs `next build --webpack`. `next.config.ts` enables `output: 'standalone'`, and `pnpm-workspace.yaml` records the pnpm 10.12.4 `ignoredBuiltDependencies` policy used during the frozen install.

To exercise the same standalone server artifact outside Docker after a build, stage the static assets that the container copies and run the black-box regression:

```sh
cp -R public .next/standalone/public
mkdir -p .next/standalone/.next
cp -R .next/static .next/standalone/.next/static
./scripts/test-container-runtime.sh
```

## Docker build and run

From this directory:

```sh
docker build --build-arg PNPM_VERSION=10.12.4 -t recover-works-next .
docker run --rm -p 3000:3000 recover-works-next
```

The image performs a frozen pnpm install, runs the Webpack build, copies `public`, `.next/standalone`, and `.next/static` into a minimal runtime stage, and starts `node server.js` as the non-root `node` user on port 3000. In the full stack, `compose.yaml` builds and starts this image and Caddy proxies `next.recover.works` to it.
