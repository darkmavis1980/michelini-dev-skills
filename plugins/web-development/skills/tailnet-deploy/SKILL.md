---
name: tailnet-deploy
description: Set up, fix or review a GitHub Actions deploy to a self-hosted server that is reachable only through Tailscale (a home server, a NAS, a box on a private tailnet), running the app with Docker Compose. Covers the Tailscale GitHub Action with workload identity federation (OIDC, no Tailscale secret), a locked-down tag:ci policy, normal SSH with a deploy key and a pinned host key, settings in a GitHub Environment (app path, port, compose project per app), pushing the exact commit to the server, and a deploy script that is safe on a machine shared with other apps. Use this whenever the user wants to deploy to QA, staging or a preview environment on their own hardware, mentions Tailscale or a tailnet together with GitHub Actions, CI/CD or deploys, asks how GitHub can reach a machine behind NAT without opening ports, or a deploy like this fails ("No ED25519 host key is known", "port is already allocated", tailscale login errors, commit not found on the server).
---

# Deploy to a self-hosted server over Tailscale

The shape this sets up:

```
push to <branch> (or a tag) ──► CI workflow
  <check-job>       : the existing build / test job
  deploy-<env>      : needs <check-job>, runs in GitHub Environment <env> (holds every setting)
     1. check settings     strict regex on every value that will reach a shell
     2. join the tailnet   tailscale/github-action, OIDC, tag:ci, ephemeral node
     3. SSH                deploy key + known_hosts from secrets, StrictHostKeyChecking=yes
     4. git push           <sha> ──► <app path>:refs/deploy/<env>   (server never needs repo access)
     5. deploy             ssh 'bash -s -- <path> <sha> <port> <project>' < scripts/deploy-compose.sh
     6. on failure         compose ps + logs
Server: checkout <sha> in its own clone ─► docker compose -p <project> up -d --build --wait ─► curl the port
Tailscale policy: tag:ci may reach only tcp:22 on that one host.
```

Files: [templates/deploy-job.yml](templates/deploy-job.yml) (the job), [templates/deploy.sh](templates/deploy.sh) (the server script), [scripts/host-key-line.sh](scripts/host-key-line.sh) (prints the `known_hosts` line and its fingerprint). Why each piece is the way it is, the one-time setup, the failures this design already hit and the review checklist are in [REFERENCE.md](REFERENCE.md).

## Setting it up

1. **Read the repo first.** Find the workflow that runs the checks and the job name to depend on, `compose.yaml` / `docker-compose.yml` (service, container port, is there a `healthcheck` in it or in the `Dockerfile`), any existing deploy workflow, and docs folders (ADRs, plans). Keep what works.
2. **Fix the parameters with the user.** Ask only for what the repo doesn't tell you:
   - environment name (default `qa`) and what triggers it (default: push to `main`; a tag `v*` or `workflow_dispatch` also work);
   - whether the server runs other apps (assume yes: the script is built for a shared machine);
   - how people will open it: a host port on the LAN only, or a Cloudflare Tunnel / reverse proxy to a domain. Ask where that proxy runs; if it runs in Docker, the app must listen on `0.0.0.0` (REFERENCE, "Bind address").
   Don't ask for hostnames, users or paths. They go in GitHub settings, not in the repo.
3. **Make the port configurable in compose.** Change the service's `ports` line to `"${HOST_BIND:-0.0.0.0}:${HOST_PORT:-<current host port>}:<container port>"`, so local `docker compose up` behaves as before. If the image has no healthcheck, add one (`--wait` needs it to mean "the app answers", not just "the process started").
4. **Copy and fill the templates.** Replace every `<placeholder>`:
   - [templates/deploy.sh](templates/deploy.sh) → `scripts/deploy-compose.sh` (`chmod +x`). Set the app name in the header. If the app's health URL is not `/`, change the final curl.
   - [templates/deploy-job.yml](templates/deploy-job.yml) → add the job under `jobs:` of the check workflow. Keep its settings names (`DEPLOY_*`): they live in the Environment, so a second environment reuses them with different values. If the repo already has a deploy of this kind with its own names, keep those instead.
   - Look up the current majors of `actions/checkout` and `tailscale/github-action` (releases pages, or context7) and match the versions other workflows in the repo use.
5. **Validate locally.** `bash -n scripts/deploy-compose.sh`; shellcheck if installed; actionlint (`docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:<exact version>` runs shellcheck on `run:` blocks too); `HOST_PORT=7599 docker compose config` shows the new port. If Docker is available, the script can be tested against a throwaway clone with a free port and a unique project name (REFERENCE, "Testing locally").
6. **Give the user the one-time setup** from [REFERENCE.md](REFERENCE.md#one-time-setup-user-steps): server, Tailscale policy, Tailscale trust credential, GitHub Environment, optional tunnel. Fill in the repo's `owner/name` and environment in the OIDC subject. Give the user the settings table with the values you know. These are their steps.
7. **Record it** where the repo records decisions (an ADR, the README's deploy section, the CLAUDE.md / AGENTS.md commands list), including "never run this deploy against the server yourself" for agents.

## When a deploy fails

Match the error to [REFERENCE.md](REFERENCE.md#when-it-fails) before changing code: most first-run failures are settings, not bugs. Explain which side the fix is on (GitHub setting, Tailscale console, server, repo). A GitHub "Re-run" uses the workflow file of the old commit, so after a workflow fix the user needs a new run (`gh workflow run <workflow> --ref <branch>` or a new push).

## Reviewing an existing setup

Go through the [review checklist](REFERENCE.md#review-checklist) and report each item as ok / gap with `file:line`. Fix gaps only after the user agrees.

## Rules

- Never run the deploy, SSH to the server, change Tailscale or GitHub settings, or set secrets. Give the user the exact steps or commands. Read-only checks the user explicitly asks for are fine; say first what will run.
- No `${{ … }}` inside `run:` blocks. Every GitHub value goes through `env:` and is used as `"$VAR"`, which stops script injection.
- Every value that reaches the remote shell is checked with a strict regex, on the runner and again in the script.
- Host keys are always checked (`StrictHostKeyChecking=yes` plus a `known_hosts` secret). Never `StrictHostKeyChecking=no`.
- On a shared server, the deploy touches only its app folder and its compose project: no `docker system prune`, no global image prune, no `sudo`, nothing outside the folder.
- No real hostnames, tailnet names, IPs, usernames or paths in the repo or in examples. They belong in the GitHub Environment.
