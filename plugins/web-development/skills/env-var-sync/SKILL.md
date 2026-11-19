---
name: env-var-sync
description: Check that every server env var is declared in all the places that inject env (apps/<app>/.env.sample, apps/<app>/.env.docker, and the PM2 ecosystem.config.sample.js) and fix the gaps. Use this whenever you add, rename or remove an environment variable in a Node/Express app, when the user asks to "add an env var", "check env files", "sync .env", or after a change that reads a new process.env value — a var missing from the PM2 file silently breaks the non-Docker production deploy. Also run it before finishing any change that touched process.env.
---

# Env var sync

In these repos env reaches the server three ways, and each needs every key:

| File | Who reads it |
|---|---|
| `apps/<app>/.env.sample` (or `.env.example`) | Copied to `.env` for local dev. **Source of truth** for which keys exist. |
| `apps/<app>/.env.docker` | `env_file` of the app's service in `docker-compose.yml`. |
| `ecosystem.config.sample.js` (repo root) | PM2 in the non-Docker prod deploy. The **only** env source there, so a missing key fails at runtime with no warning at deploy. |

## Check

Run the bundled script from the repo root. It is read-only, prints key names only (never values), and exits 1 if anything is missing:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/env-var-sync/scripts/check-env-sync.mjs" .
node "${CLAUDE_PLUGIN_ROOT}/skills/env-var-sync/scripts/check-env-sync.mjs" . --ignore DB_EXPOSE_PORT
node "${CLAUDE_PLUGIN_ROOT}/skills/env-var-sync/scripts/check-env-sync.mjs" . --app apps/server
```

- It finds every `apps/*/.env.sample`, compares it to that app's `.env.docker` (if there is one) and to the PM2 app block whose `cwd` is that app.
- `MISS` lines are real gaps. `info` lines list keys set only in the target (`NODE_ENV`, `PORT` in PM2 are normal).
- `--ignore` is for keys that belong in only one place, such as compose-only variables like `DB_EXPOSE_PORT`.
- A root `.env.sample` is only checked in a single-app repo, or with `--app .`. In a monorepo it usually holds tooling keys.

## Adding a var

1. Read it in code with a safe default or a clear startup error. Don't fall back to an insecure default for secrets.
2. Add it to `.env.sample` with a comment saying what it is and how to generate it if it is a secret (e.g. `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`).
3. Add it to `.env.docker` with a value that works inside compose (service hostnames like `db`, `redis`, not `localhost`).
4. Add it to the right `env` block in `ecosystem.config.sample.js` with a `replace-me` placeholder for secrets. Secrets in the sample need a `// bearer:disable ...` comment only if the repo already uses Bearer and flags it.
5. Run the check again. It must pass.
6. Tell the user they must add the real value to the server's `ecosystem.config.js` (not in git) before the next deploy, or the release will start without it.

Never write real secret values into any of these files. They are samples.

## Removing or renaming a var

Remove it from all three files in the same change, and search the codebase (`grep -rn "process.env.OLD_NAME"`) so no reader is left behind. For a rename, mention that the server's real `ecosystem.config.js` and `.env` need the same rename.
