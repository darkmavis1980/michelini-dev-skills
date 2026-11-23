# web-development

Conventions and tools for full-stack TypeScript npm-workspaces monorepos: an Express 5 + Kysely + Postgres API in `apps/server`, Vite or Next.js frontends, an optional Cloudflare Worker, deployed to one VPS with GitHub Actions, PM2 and nginx. Drawn from the layout shared by the author's own monorepos.

## Skills

| Skill | What it does |
| --- | --- |
| `npm-workspaces-monorepo` | Scaffolds a new monorepo in the house layout, or adds an app to an existing one with a checklist of everything else a new app touches (root scripts, ports, Dockerfile, compose, nginx, CI matrix, CLAUDE.md). Templates: root `package.json`, `docker-compose.yml`, server and SPA Dockerfiles, SPA nginx config, `.dockerignore`, `CLAUDE.md`. |
| `express-api-conventions` | Thin zod-validated routes, services that own logic and queries, `AppError`, Zod v4 formats, Kysely migrations that the user runs, tests in `tests/` mirroring `src/`. `REFERENCE.md` has the code shapes. |
| `env-var-sync` | Checks every key in `apps/*/.env.sample` is also in `.env.docker` and the matching PM2 block of `ecosystem.config.sample.js`. Script: `check-env-sync.mjs` (read-only, prints key names only, exits 1 on a gap). |
| `vps-release-pipeline` | Sets up or reviews PR checks, a release workflow that checks and deploys the exact tag (pinned SSH host key, rollback by tag), `update.sh`, the PM2 sample and the nginx sample. `REFERENCE.md` explains each choice and has a review checklist. |
| `tailnet-deploy` | Deploys to a self-hosted server reachable only through Tailscale (home server, QA, staging): a GitHub Actions job using the Tailscale action with OIDC (no Tailscale secret), SSH with a pinned host key, settings in a GitHub Environment, the commit pushed to the server, and a Docker Compose deploy script that is safe on a machine shared with other apps (input checks, port check, own compose project). Script: `host-key-line.sh` (prints the `known_hosts` line and fingerprint). `REFERENCE.md` has the one-time setup, the Tailscale policy, a failure table and a review checklist. |
| `markdown-for-agents` | Serves every page as Markdown to agents: `Accept: text/markdown` negotiation with q-values, ties to Markdown, 406, `Vary: Accept`, `.md` twins and `llms.txt` links. Templates for nginx `map` blocks (static/SSG, no njs), Next.js proxy + route handler, Express middleware, Vite dev plugin, a turndown post-build converter, and the shared parser with tests. Script: `check-markdown.sh` (read-only, runs the acceptmarkdown-style cases against any URL). |

## Guard hook (opt-in)

A `PreToolUse` hook on Bash that blocks commands a project doesn't want Claude to run. It does nothing until a project opts in with `.claude/guards.json`:

```json
{ "block": ["migrations", "git-write"] }
```

| Rule | Blocks | Still allowed |
| --- | --- | --- |
| `migrations` | `migrate:up/down/latest/rollback/reset`, `prisma migrate deploy/dev/reset`, `prisma db push`, `drizzle-kit push/migrate`, `sequelize db:migrate`, `knex migrate:*` | `migrate:status`, `migrate:create` |
| `git-write` | `git commit`, `git push` (with any flags, `-C <dir>`, inside `&&` chains) | every other git command |

When it blocks a command, Claude gets a message saying why and what to do instead (write the migration and give the user the command, or leave changes uncommitted). It catches mistakes but isn't a security boundary: a determined workaround (a script that runs the command) isn't detected.

## Requirements

- Node.js 24+ for the hook and `check-env-sync.mjs`; `bash` and `curl` for `check-markdown.sh`. If `node` is missing the hook fails open (doesn't block).

## Install

```
/plugin install web-development@michelini-dev-skills
```
