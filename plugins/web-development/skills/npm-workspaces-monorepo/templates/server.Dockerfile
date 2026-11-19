# apps/server/Dockerfile. Build context is the repo root (see docker-compose.yml)
# so the root package-lock.json is used.
FROM node:24-alpine
WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/server/package.json ./apps/server/package.json

# Installs only this workspace's dependencies from the root lockfile, dev ones included:
# `npm start` runs through tsx, so don't add --omit=dev unless tsx is in "dependencies".
RUN npm ci --workspace=apps/server
# Set after the install: NODE_ENV=production makes npm ci skip devDependencies.
ENV NODE_ENV=production

COPY apps/server ./apps/server

# Drop root. If the server writes to local disk (uploads, caches), chown that folder to node first.
USER node
WORKDIR /app/apps/server
EXPOSE 3001
CMD ["node", "--import", "tsx/esm", "src/index.ts"]
