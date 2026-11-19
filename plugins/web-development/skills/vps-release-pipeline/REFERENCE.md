# VPS release pipeline: reasons and review checklist

## Why each piece is the way it is

**Checks before deploy (`check` job, `needs: check`).** A release is a tag someone picked by hand, and it may not be the commit the last PR run tested. Running typecheck, lint, test and build on the tag itself is the last gate before production. Without it, a broken tag deploys and the build fails on the server, sometimes after the static files have been half replaced.

**Deploy the tag, not `main`.** `git pull origin main` on the server deploys whatever `main` is at that minute, which can be newer than the release. `git fetch --tags --force && git checkout --detach refs/tags/$TAG` deploys exactly what `check` tested. It also makes rollback simple: run the workflow by hand with an older tag.

**Validate the tag string.** `$TAG` is placed into a remote shell command. The regex `^[A-Za-z0-9._/-]+$` stops a crafted tag name from injecting commands.

**Pinned host key instead of `StrictHostKeyChecking=no`.** With checking off, the runner sends the deploy key to whatever answers on that IP. Store `ssh-keyscan -p <port> <host>` output in `SSH_KNOWN_HOSTS`, check it once against the fingerprint the server shows (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), and the runner will refuse a different server.

**`concurrency: deploy-production`, `cancel-in-progress: false`.** Two releases in a row must not run `npm ci` and builds in the same directory at once. The second one waits.

**`release: types: [published]`.** `created` also fires when a draft is saved. `published` fires once, when the release becomes public.

**`npm ci` on the server, not `npm install`.** `npm install` can rewrite `package-lock.json` on the server, which leaves the checkout dirty and makes the next `git checkout` fail or need a `git stash`. `npm ci` installs exactly the lockfile. If `npm ci` fails on Linux because of missing optional native bindings (rolldown, esbuild, sharp), add the Linux packages to root `optionalDependencies` and regenerate the lockfile. Don't switch back to `npm install`.

**No `git stash` in the deploy.** A stash hides local edits on the server without telling anyone, and they pile up. The server checkout should have no tracked-file edits. Config that differs per server (`ecosystem.config.js`, `.env`) is untracked.

**Migrations before restart, while the old server runs.** The old pattern stopped the server (`pm2 delete`), then ran migrations, then started it. The site is down for the whole migration, and stays down if the migration fails. Running `migrate:up` first keeps the old server up. If the migration fails, `set -e` stops the script and the old version keeps serving. This needs migrations that are backward compatible with the old code (expand, then contract in a later release). The server also runs `migrateToLatest()` on start, so the explicit step is there to fail loudly before the restart, not to be the only path.

**`pm2 startOrReload ecosystem.config.js --update-env`.** This starts apps that aren't running, reloads ones that are, and picks up env changes from `ecosystem.config.js`. `pm2 save` keeps the process list across reboots.

**Static apps served by nginx straight from `dist/`.** No Node process for SPAs. Hashed `/assets/` get `try_files $uri =404` so a stale tab gets a real 404 for an old chunk (and can reload) instead of `index.html` served as JavaScript.

**PR checks: one root `npm ci`, a workspace matrix.** One job per workspace repeats the same YAML four times. A matrix with `--if-present` runs only the scripts each workspace has, and `fail-fast: false` shows every failing workspace at once.

## Rollback

Actions → Release → Run workflow → enter the previous tag. This redeploys code only. Migrations don't roll back. If the bad release ran a migration the old code can't handle, the user must write and run a new forward migration (or `migrate:down` by hand, with a backup). Before a risky migration, the user should run the backup script (`scripts/backup_postgres.sh` in these repos).

## Review checklist

Report each item as **ok** or **gap** with `file:line`.

### release.yml
- [ ] Triggers on `release: published` (not `created`) and `workflow_dispatch` with a `tag` input
- [ ] `permissions: contents: read` at the top
- [ ] `concurrency` group for production deploys, `cancel-in-progress: false`
- [ ] A `check` job that checks out the tag and runs typecheck, lint, test, build; deploy jobs have `needs: check`
- [ ] The tag is validated with a strict regex before it goes into a shell command
- [ ] SSH uses a pinned `known_hosts` (no `StrictHostKeyChecking=no`)
- [ ] The server checks out the tag (`git checkout --detach refs/tags/$TAG`), not `git pull origin main`
- [ ] The private key file is removed in an `if: always()` step
- [ ] Worker deploys (if any) also `needs: check` and deploy from the tag

### pr-checks.yml
- [ ] Runs on `pull_request`, `permissions: contents: read`, `concurrency` cancels older runs on the same PR
- [ ] Every workspace that has `typecheck` / `lint` / `test` / `build` scripts runs them (compare with each `apps/*/package.json`)
- [ ] `npm ci` (lockfile) with `actions/setup-node` npm cache
- [ ] Node version matches production and the Dockerfiles

### scripts/update.sh
- [ ] `set -euo pipefail`
- [ ] No `git stash`, no second `git pull` when the workflow already checked out the tag
- [ ] `npm ci`, not `npm install`
- [ ] Builds every static app that nginx serves
- [ ] `migrate:up` runs before the server restart, not after `pm2 delete`
- [ ] Restart with `pm2 startOrReload ecosystem.config.js --update-env`, then `pm2 save`
- [ ] Paths come from the script's own location, not a hard-coded `/opt/...` repeated in several places

### ecosystem.config.sample.js
- [ ] Every key in `apps/server/.env.sample` is present (run the `env-var-sync` check)
- [ ] Secrets are `replace-me` placeholders with a comment on how to generate them
- [ ] `ecosystem.config.js` (the real one) is in `.gitignore`

### nginx.sample.conf
- [ ] `www` → apex 301 (or the reverse), one canonical host
- [ ] `/api/` proxied to `127.0.0.1:3001` with `X-Forwarded-For` / `X-Forwarded-Proto`, and the Express app has `trust proxy` set to match
- [ ] `client_max_body_size` sized for the largest upload route, and Express still enforces its own limits
- [ ] `/assets/` uses `try_files $uri =404`
- [ ] Security headers are included (see the `security:nginx-spa-security-headers` skill)
- [ ] Admin SPAs send `X-Robots-Tag: noindex`
