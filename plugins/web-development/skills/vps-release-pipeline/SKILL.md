---
name: vps-release-pipeline
description: Set up or review the GitHub Actions + SSH + PM2 + nginx deploy for a Node web app or npm-workspaces monorepo on a single VPS — PR checks, a release workflow that runs checks and deploys the exact release tag (with rollback by tag), the server-side update.sh, the PM2 ecosystem sample and the nginx sample, plus deploying a Cloudflare Worker from the same release. Use this whenever the user wants to add or fix CI/CD, "deploy on release", "set up GitHub Actions", "the deploy broke", "roll back a release", edits release.yml / pr-tests.yml / update.sh / ecosystem.config / nginx.sample.conf, or asks whether their deploy pipeline is safe.
---

# VPS release pipeline

The shape this sets up:

```
PR opened ──► pr-checks.yml: npm ci, then typecheck / lint / test / build per workspace
GitHub release published (tag vX.Y.Z) ──► release.yml
   check   : checkout the tag, same checks as PRs
   deploy  : needs check ─► SSH (pinned host key) ─► git checkout --detach <tag> ─► scripts/update.sh
   worker  : needs check ─► wrangler deploy (if the repo has a Worker app)
Server: scripts/update.sh ─► npm ci ─► build static apps ─► migrate:up ─► pm2 startOrReload
nginx serves the static builds and proxies /api/ to the PM2 server on 127.0.0.1:3001
```

Templates are in [templates/](templates/). The reasons behind each choice, and the checklist for reviewing an existing pipeline, are in [REFERENCE.md](REFERENCE.md).

## Setting it up

1. Read the repo first: root `package.json` (workspaces, scripts), each `apps/*/package.json` (which have `typecheck`, `lint`, `test`, `build`), `docker-compose.yml`, any existing `.github/workflows/`, `scripts/update.sh`, `ecosystem.config.sample.js`, `nginx.sample.conf`. Keep what already works; change only what the review checklist flags.
2. Copy and fill the templates. Replace every `<placeholder>`:
   - [templates/pr-checks.yml](templates/pr-checks.yml) → `.github/workflows/pr-checks.yml`. Set the `workspace` matrix to the apps that exist.
   - [templates/release.yml](templates/release.yml) → `.github/workflows/release.yml`. Set `APP_DIR`. Delete the `deploy-worker` job if there is no Worker.
   - [templates/update.sh](templates/update.sh) → `scripts/update.sh` (`chmod +x`). Set the build commands.
   - [templates/ecosystem.config.sample.js](templates/ecosystem.config.sample.js) → repo root. Copy the env keys from `apps/server/.env.sample`, then run the `env-var-sync` skill's check.
   - [templates/nginx.sample.conf](templates/nginx.sample.conf) → repo root. One `server` block per public host.
3. List what the user must set in GitHub (repo → Settings → Secrets and variables → Actions). Don't set them yourself:
   - Secrets: `SSH_PRIVATE_KEY` (a deploy-only key), `SSH_KNOWN_HOSTS` (output of `ssh-keyscan -p <port> <host>`, checked against the server's real fingerprint), and `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` if there is a Worker.
   - Variables: `SSH_HOST`, `SSH_PORT`, `SSH_USER`.
   - Optional: a `production` environment with required reviewers, to approve each deploy.
4. Tell the user the one-time server steps (they run them): clone the repo to `APP_DIR`, copy `ecosystem.config.sample.js` to `ecosystem.config.js` and fill in real secrets, `pm2 startup` + `pm2 save`, install the nginx config and get TLS certs.
5. Validate locally: `npx --yes actionlint` if available, `bash -n scripts/update.sh`, and `nginx -t` only if the user has nginx locally.

## Reviewing an existing pipeline

Go through the checklist in [REFERENCE.md](REFERENCE.md#review-checklist) and report each item as ok / gap, with the file and line. Fix gaps only after the user agrees, because the deploy is shared infrastructure.

## Rules

- Never run the deploy, `ssh` to the server, or create releases or tags. The user does those.
- Never put secrets in workflow files, samples or commit messages. Samples use `replace-me`.
- Migrations in the deploy must be backward compatible with the old server, because `migrate:up` runs before the restart. Point this out when a PR adds a breaking migration.
- Pin action major versions (`actions/checkout@v7`) and match the versions the repo already uses. Use `permissions: contents: read` at the top of every workflow.
