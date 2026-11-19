---
name: npm-workspaces-monorepo
description: Scaffold, extend or align a full-stack TypeScript npm-workspaces monorepo in the house layout — apps/server (Express 5 + Kysely + Postgres/pgvector), apps/client and apps/admin (Vite/React or Next.js), optional apps/mcp-server (Cloudflare Worker); root overrides pinning one React, concurrently for dev, docker compose with a healthy-db dependency, Dockerfiles built from the repo root, and a CLAUDE.md with the hard rules. Use this whenever the user wants to start a new full-stack project or monorepo, "add a new app/workspace" (an admin panel, a second SPA, a Worker), move a repo to npm workspaces, fix duplicate React instances, set up docker compose for local dev, or bring a repo in line with their other monorepos.
---

# npm-workspaces monorepo

## Target layout

```
<repo>/
  package.json              # private, "workspaces": ["apps/*"], overrides: react + react-dom
  package-lock.json         # one lockfile for every app
  docker-compose.yml        # db (+ redis) + one service per app, production-like
  .dockerignore  .prettierrc  .gitignore
  ecosystem.config.sample.js  nginx.sample.conf  scripts/update.sh   # see vps-release-pipeline
  CLAUDE.md  CONTEXT.md     # rules + domain glossary
  docs/adr/  docs/plans/  docs/mental-model.md
  apps/
    server/      Express 5 API, TS ESM, tsx, port 3001, Dockerfile, .env.sample, .env.docker
    client/      public site: Vite + React 19 (port 5173) or Next.js (port 3000)
    admin/       admin SPA, Vite + React 19, port 5174, built static, nginx in Docker
    mcp-server/  optional Cloudflare Worker over the public API (wrangler)
```

Ports: server 3001, client 5173 (Vite) or 3000 (Next), admin 5174, further SPAs 5175 and up. Docker publishes the client on 8079, admin on 8078, further apps on 8077 and down. Every app stays under `apps/`. Never move one out.

Templates for each file are in [templates/](templates/):
[root-package.json](templates/root-package.json) ·
[docker-compose.yml](templates/docker-compose.yml) ·
[server.Dockerfile](templates/server.Dockerfile) ·
[spa.Dockerfile](templates/spa.Dockerfile) ·
[spa-nginx.conf](templates/spa-nginx.conf) ·
[dockerignore](templates/dockerignore) ·
[CLAUDE.md.template](templates/CLAUDE.md.template)

## New monorepo

1. Ask only what the templates can't infer: project name, which frontend apps (client, admin, others), Vite or Next for the client, whether there is a Worker, Redis or pgvector.
2. Look up current versions with context7 (`resolve-library-id` then `query-docs`) for every dependency you add, and pin the exact latest patch (`^8.0.7`, not `^8.0.0`).
3. Create the root files from the templates, then each app. Scaffold frontends with their own tools (`npm create vite@latest apps/admin -- --template react-ts`, `npx create-next-app@latest apps/client`), then remove each app's own lockfile and `.git`. Only the root lockfile stays.
4. Server: follow the `express-api-conventions` skill for its layout (errors, routes, services, migrator, tests).
5. Write `CLAUDE.md` from the template. Fill in only what is true now and delete sections that don't apply.
6. Add the deploy files with the `vps-release-pipeline` skill.
7. `npm install` from the root, then run every workspace's `typecheck` and `build` and fix what fails. Don't start the dev servers unless the user asks.

## Add an app to an existing monorepo

Every new app touches more than its own folder. Go through this list and tell the user which items you changed and which you skipped:

- [ ] `apps/<name>/package.json` with a unique `name`, and `dev`, `build`, `typecheck`, `lint` scripts
- [ ] Root `package.json`: `dev:<name>` script, add it to the `concurrently` `dev` line (`-n` name and `-c` colour), add it to `build`, `typecheck` and `lint` if those exist at the root
- [ ] Vite `server.port` set to the next free port, and `/api` proxied to `http://localhost:3001` in `vite.config.ts`
- [ ] Dockerfile from the template, plus an `apps/<name>/nginx.conf` for static apps
- [ ] `docker-compose.yml` service with the next free host port
- [ ] `nginx.sample.conf` server block, and the build line in `scripts/update.sh`
- [ ] `.github/workflows/pr-checks.yml` matrix entry
- [ ] Cross-subdomain auth: if the app is on its own subdomain and shares the login cookie, add its origin to `ALLOWED_ORIGINS` and use the `env-var-sync` skill for any new key
- [ ] `CLAUDE.md` repo layout section, and `docs/mental-model.md` (suggest `dev-workflow:mental-model`)

## Rules worth keeping

- **One React.** Root `"overrides": { "react": "^19.x.y", "react-dom": "^19.x.y" }`. Without it a workspace can install a second copy and hooks fail with "Invalid hook call". After changing it: `rm -rf node_modules apps/*/node_modules && npm install`.
- **Install from the root**: `npm install <pkg> -w apps/<name>`. Never run `npm install` inside an app folder, because it creates a second lockfile.
- **Dockerfiles build from the repo root** (`context: .`, `dockerfile: apps/<name>/Dockerfile`) so they can use the root lockfile with `npm ci --workspace apps/<name>`.
- **Native optional binaries** (rolldown, esbuild, sharp) can be missing from a lockfile made on macOS, and then `npm ci` fails on Linux. If that happens, list the Linux packages in root `optionalDependencies` and regenerate the lockfile.
- **Same-origin `/api`** in every environment: the Vite or Next dev proxy, nginx in Docker and in prod. So there is no CORS in production, and the frontend calls relative `/api/...`.
- **Prettier at the root** with `format:changed` (`git diff --name-only HEAD | xargs prettier --write --ignore-unknown`), so a reformat stays inside the change. Don't run a whole-tree format on an existing repo.
- **ESLint flat config per workspace**, clean at `--max-warnings 0`. If a rule doesn't fit, turn it off in the config with a written reason.
