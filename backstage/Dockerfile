# --- stage 1: build --------------------------------------------------------
FROM public.ecr.aws/docker/library/node:20-bookworm-slim AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3 g++ build-essential libsqlite3-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN corepack enable

# Copy manifests first for a cacheable dependency install. corepack + the
# packageManager field in package.json provide yarn 4 — no .yarn/releases to copy.
COPY .yarnrc.yml package.json yarn.lock backstage.json ./
COPY packages/app/package.json packages/app/package.json
COPY packages/backend/package.json packages/backend/package.json

RUN yarn install --immutable

# Now the sources, and build EVERYTHING (app + backend). build:all compiles the
# frontend app into packages/app/dist (served by app-backend) and bundles the
# backend into packages/backend/dist/*.tar.gz.
COPY . .
RUN yarn tsc && yarn build:all

# --- stage 2: runtime ------------------------------------------------------
FROM public.ecr.aws/docker/library/node:20-bookworm-slim

# TechDocs local generator (mkdocs) — only used when techdocs.generator.runIn: local.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv g++ build-essential libsqlite3-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    python3 -m venv /opt/techdocs && \
    /opt/techdocs/bin/pip install --no-cache-dir mkdocs-techdocs-core
ENV PATH="/opt/techdocs/bin:${PATH}"

RUN corepack enable

USER node
WORKDIR /app

# Install prod deps against the compiled skeleton, then unpack the bundle.
COPY --chown=node:node --from=build /app/.yarn ./.yarn
COPY --chown=node:node --from=build /app/.yarnrc.yml /app/backstage.json /app/package.json /app/yarn.lock ./
COPY --chown=node:node --from=build /app/packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz && \
    yarn workspaces focus --all --production && yarn cache clean

COPY --chown=node:node --from=build /app/packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

COPY --chown=node:node --from=build /app/packages/app/dist ./packages/app/dist

# app-config.yaml is the base; app-config.production.yaml overlays prod.
COPY --chown=node:node app-config.yaml app-config.production.yaml ./
COPY --chown=node:node catalog ./catalog

ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

EXPOSE 7007
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
