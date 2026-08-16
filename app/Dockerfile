FROM node:24-bookworm-slim AS base
ARG PNPM_VERSION=10.12.4
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable
WORKDIR /app

FROM base AS dependencies
ARG PNPM_VERSION=10.12.4
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack pnpm@${PNPM_VERSION} install --frozen-lockfile

FROM dependencies AS build
ARG PNPM_VERSION=10.12.4
COPY . .
RUN corepack pnpm@${PNPM_VERSION} build

FROM base AS runtime
ENV HOST=0.0.0.0
ENV PORT=4321
ENV NODE_ENV=production
RUN chown node:node /app
COPY --chown=node:node --from=build /app/dist ./dist
COPY --chown=node:node --from=build /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/package.json ./package.json
USER node
EXPOSE 4321
CMD ["node", "./dist/server/entry.mjs"]
