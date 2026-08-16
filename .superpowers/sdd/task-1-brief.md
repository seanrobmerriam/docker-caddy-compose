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

