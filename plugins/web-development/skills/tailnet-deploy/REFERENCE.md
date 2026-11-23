# Tailnet deploy: reasons, setup, failures and review

Contents: [Why each piece](#why-each-piece-is-the-way-it-is) · [Settings](#github-environment-settings) · [One-time setup](#one-time-setup-user-steps) · [Testing locally](#testing-locally) · [When it fails](#when-it-fails) · [Review checklist](#review-checklist)

## Why each piece is the way it is

**Tailscale instead of opening a port.** The server sits behind a home router or NAT. The runner joins the tailnet for the length of the job as an ephemeral node, reaches the server on its tailnet name, and is removed afterwards. Nothing on the server is open to the internet.

**Workload identity federation (OIDC), not an OAuth client secret or auth key.** GitHub gives the job a short-lived signed token (`permissions: id-token: write`); Tailscale trusts tokens whose subject matches the trust credential. There is no long-lived Tailscale secret in GitHub to leak or rotate. `TS_OAUTH_CLIENT_ID` and `TS_AUDIENCE` are identifiers, kept as secrets only to keep them out of logs.

**The OIDC subject includes the Environment.** When a job has `environment: <env>`, GitHub's token subject is `repo:<owner>/<repo>:environment:<env>`, not `…:ref:refs/heads/main`. The trust credential must use that exact subject, or login fails.

**`tag:ci` may reach only `tcp:22` on one host.** The default policy allows everything to everything. Then every CI runner could reach every device on the tailnet, including the other apps on the same server. The grant plus a `tests` block makes the limit explicit, and the policy refuses to save if a test fails.

**Normal SSH with a deploy key, not Tailscale SSH.** Tailscale SSH needs no key in GitHub, but the server would need a tag (tagged devices lose their user owner, and the access rules for everything else on it change). A dedicated deploy key, used for nothing else, is simpler on a shared machine.

**Pinned host key.** With `StrictHostKeyChecking=no` the runner would send its key to whatever answers on that name. The `known_hosts` secret holds the server's real public key, checked once by hand against the server's own fingerprint.

**Settings in a GitHub Environment.** The app path, port and compose project differ per server and per app, so they are settings, not code. An Environment also limits which branches may deploy (Deployment branches → selected branches), shows each deployment, and can require a reviewer. One set of `DEPLOY_*` names works for every environment.

**Validate everything twice.** The values are placed into a remote shell command. A variable like `/srv/x; rm -rf ~` must be refused on the runner before SSH, and again by the script in case it is run by hand.

**Push the commit to the server (`refs/deploy/<env>`).** The server's clone may be unable to fetch the commit: the repo is private, or the clone's `origin` is another remote (a Gitea mirror) that hasn't got the commit yet. Pushing over the same SSH connection needs no extra key and works wherever the PR was merged. It needs `fetch-depth: 0` on checkout, or the push from a shallow clone can be refused. The ref is moved by force on every deploy; nothing else should use it.

**Stream the script from the runner (`bash -s -- args < script`).** The server always runs the script version from the commit being deployed. There is nothing to install or keep in sync on the server.

**One compose project per app and environment (`-p`).** Two apps with the same project name or port would replace each other's containers. The project name and port are settings, so each app gets its own.

**Port check before anything changes.** If another project or process holds the port, `docker compose up` fails only after the checkout has changed. The script refuses early (exit 68) and names who holds it.

**`git reset --hard` + `git clean -fdx -e .env`, then `checkout --detach`.** Someone may have edited files in the server's clone. The build must be exactly the commit. An untracked `.env` for server-only settings is kept.

**`up -d --build --wait --remove-orphans`.** Compose replaces the running container only after the new image builds, so a broken build leaves the old version serving. `--wait` fails the job if the healthcheck does not pass in time. The final curl checks the published port, not only the container.

**Bind address.** If the tunnel or reverse proxy runs as a host service, `127.0.0.1` is enough and safer. If it runs as a Docker container in its own network (common with `cloudflared` on home servers), `127.0.0.1` on the host is not reachable from it: bind `0.0.0.0` and point the proxy at `http://<server LAN IP>:<port>`. That also exposes the port on the LAN; say so to the user.

**No image prune.** Old images of this project pile up slowly. A global prune would delete other apps' images and stopped containers. Clean by hand.

**One deploy at a time.** `concurrency: deploy-<env>` with `cancel-in-progress: false` queues a second merge; it then deploys its own, newer commit.

**Accepted risk: the deploy user is in the `docker` group.** That is root-equivalent on the server. Limits: a key for this only, `tag:ci` reaches only port 22, and the Environment deploys only from the chosen branch. Fine for QA on a home box; say it plainly.

## GitHub Environment settings

Repo → Settings → Environments → `<env>`. Deployment branches: selected branches → the trigger branch (or tag pattern).

| Kind | Name | Example | Notes |
| --- | --- | --- | --- |
| Variable | `DEPLOY_HOST` | `qa-box.tailXXXX.ts.net` | MagicDNS name (or `100.x` IP). Must match the name in `known_hosts` exactly |
| Variable | `DEPLOY_SSH_PORT` | `22` | sshd port on the server |
| Variable | `DEPLOY_SSH_USER` | `deploy` | dedicated deploy user |
| Variable | `DEPLOY_APP_PATH` | `/srv/apps/my-app` | the app's own git clone on the server |
| Variable | `DEPLOY_HTTP_PORT` | `7500` | host port; must be free on the server (1024–65535) |
| Variable | `DEPLOY_COMPOSE_PROJECT` | `my-app-qa` | unique compose project name on that server |
| Secret | `DEPLOY_SSH_PRIVATE_KEY` | `-----BEGIN OPENSSH PRIVATE KEY-----…` | private half of the deploy key, whole file |
| Secret | `DEPLOY_SSH_KNOWN_HOSTS` | `qa-box.tailXXXX.ts.net ssh-ed25519 AAAA…` | the line from `scripts/host-key-line.sh`, not the fingerprint |
| Secret | `TS_OAUTH_CLIENT_ID` | | client ID of the Tailscale trust credential |
| Secret | `TS_AUDIENCE` | | audience of the Tailscale trust credential |

## One-time setup (user steps)

Give these to the user with the repo's real `owner/name` and environment filled in. Claude does none of them.

1. **Server.**
   - Install Docker Engine with Compose v2, git, and curl or wget. Install Tailscale and join the tailnet; note the MagicDNS name (→ `DEPLOY_HOST`) and the `100.x` IP.
   - Create (or pick) the deploy user and add it to the `docker` group.
   - Clone the repo as that user into the app folder (→ `DEPLOY_APP_PATH`). The clone does not need to fetch: the job pushes the commit.
   - Pick a free port and project name. On a shared server check first: `ss -ltn | grep ':<port> '` and `docker ps --format '{{.Names}} {{.Ports}}'`, `docker compose ls`.
   - If an old copy of the app was started by hand from that folder, stop it (`docker compose -p <old project> down`), or the first deploy will clash on the port.
2. **Deploy key** (on the user's own machine): `ssh-keygen -t ed25519 -C <app>-<env>-deploy -f ~/.ssh/<app>_<env>_deploy -N ''`. Put the `.pub` in the deploy user's `~/.ssh/authorized_keys` on the server (`ssh-copy-id -i <key>.pub user@host`). The private file goes in `DEPLOY_SSH_PRIVATE_KEY`.
3. **Host key:** run `scripts/host-key-line.sh <DEPLOY_HOST> <port>` from a tailnet device, then `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` **on the server**. Fingerprints match → paste the printed line (not the fingerprint) into `DEPLOY_SSH_KNOWN_HOSTS`.
4. **Tailscale policy** (admin console → Access controls):

   ```jsonc
   "tagOwners": {
     "tag:ci": ["autogroup:admin"],
   },
   "hosts": {
     "deploy-server": "100.x.y.z",
   },
   "grants": [
     // GitHub Actions runners may reach only SSH on the deploy server.
     { "src": ["tag:ci"], "dst": ["deploy-server"], "ip": ["tcp:22"] },
   ],
   "tests": [
     { "src": "tag:ci", "accept": ["deploy-server:22"], "deny": ["deploy-server:80", "deploy-server:<DEPLOY_HTTP_PORT>"] },
   ],
   ```

   If the policy still has the default allow-all rule (`"src": ["*"], "dst": ["*"]`), narrow it to users (`autogroup:member`) so it does not include tags. Use the real SSH port if not 22. Merge into the existing `grants` / `acls` style of the policy.
5. **Tailscale trust credential** (admin console → Settings → Trust credentials → OpenID Connect, issuer GitHub): scope **Auth Keys: write**, tag `tag:ci`, subject `repo:<owner>/<repo>:environment:<env>`. Client ID → `TS_OAUTH_CLIENT_ID`, audience → `TS_AUDIENCE`.
6. **GitHub Environment** `<env>`: deployment branch rule, then the variables and secrets in the table above.
7. **Optional: domain through a Cloudflare Tunnel.** Public hostname → `http://<LAN IP or 127.0.0.1>:<port>` (see "Bind address"). For a non-production copy, keep it out of search engines: Cloudflare Access on the hostname, or a Transform Rule adding `X-Robots-Tag: noindex`. Leave default caching (no "Cache Everything"), or a new deploy may not show and `Vary` negotiation breaks.

Check before the first run, from the user's machine: `ssh -i <key> <user>@<DEPLOY_HOST> 'docker ps >/dev/null && git -C <DEPLOY_APP_PATH> status --short'` works with no password.

## Testing locally

With Docker, test the script against a throwaway clone before the first real run:

```bash
git clone . /tmp/deploy-test && sha=$(git rev-parse HEAD)
bash scripts/deploy-compose.sh /tmp/deploy-test "$sha" 7599 deploy-test   # expect: Deployed … port 7599
bash scripts/deploy-compose.sh /tmp/deploy-test "$sha; id" 7599 deploy-test  # expect: exit 65
docker compose -p deploy-test down --rmi local && rm -rf /tmp/deploy-test
```

Also worth a run: a modified tracked file in the clone (dropped), an untracked `.env` (kept), a port held by another container (exit 68, clone untouched). macOS has no `ss`, so the non-Docker port branch can only be tested on Linux. In zsh, write `"${sha}:refs/…"` with braces: `"$sha:r…"` is read as the `:r` modifier.

## When it fails

| Symptom | Cause | Fix (whose step) |
| --- | --- | --- |
| `DEPLOY_HOST is missing or invalid` | variable not set in that Environment, or set at repo level under another name | add it to the Environment (user) |
| Tailscale step: auth / token error | trust credential subject does not match `repo:<owner>/<repo>:environment:<env>`, missing `id-token: write`, or wrong scope / tag | fix the credential or the job permissions |
| `ping` to the host times out | policy does not let `tag:ci` reach the host, or the host is offline | policy grant / server |
| `No ED25519 host key is known for <host>` | `DEPLOY_SSH_KNOWN_HOSTS` holds a fingerprint (`SHA256:…`) or a line for another name (short name vs full MagicDNS name, IP vs name) | paste the line from `host-key-line.sh` for exactly `DEPLOY_HOST` (user) |
| `Permission denied (publickey)` | `.pub` not in the deploy user's `authorized_keys`, or the secret is not the matching private key (or is missing its last newline / header) | server / secret (user) |
| `git push` refused, shallow | checkout without `fetch-depth: 0` | repo |
| exit 66 | `DEPLOY_APP_PATH` is not a git clone | server (user) |
| exit 67 | commit not pushed and `origin` lacks it | check the push step ran; the clone's `origin` may be a mirror |
| exit 68, or compose `port is already allocated` | another project holds the port: often a copy started by hand, or the old project after `DEPLOY_COMPOSE_PROJECT` was renamed | stop the old project (`docker compose -p <old> down`), or pick another port (user) |
| `--wait` times out | healthcheck failing, or no healthcheck and the container exits | read the "Show container logs" step |
| tunnel shows 502 | app bound to `127.0.0.1` but the proxy runs in Docker, or wrong port in the tunnel | bind `0.0.0.0` and point at the LAN IP |
| "Re-run" still fails after a workflow fix | a re-run uses the old commit's workflow file | start a new run (`gh workflow run …` or a new push) |

Renaming `DEPLOY_COMPOSE_PROJECT` after a good deploy: stop the old project first, then change the variable. Otherwise the new project clashes with the running container on the same port.

## Review checklist

Report each item as **ok** or **gap** with `file:line`.

### Workflow
- [ ] Deploy job `needs:` the check job, and has an `if:` on the trigger ref
- [ ] `environment:` set; job `permissions` are `contents: read` + `id-token: write`, nothing more
- [ ] `concurrency` group per environment, `cancel-in-progress: false`
- [ ] No `${{ }}` inside any `run:` block
- [ ] Every value sent to the server checked with a strict regex before SSH
- [ ] `tailscale/github-action` on a current major, with `tags: tag:ci`, OIDC inputs (no auth key or OAuth secret), `ping`
- [ ] `StrictHostKeyChecking=yes` and `BatchMode=yes` on every ssh / git-over-ssh call
- [ ] Key written with `printf '%s\n'` from `env`, `chmod 600`; removed in an `if: always()` step
- [ ] `fetch-depth: 0` and the commit pushed to a private ref before the deploy step
- [ ] Logs step only on deploy failure (`steps.deploy.outcome == 'failure'`), ends with `|| true`

### Script
- [ ] `set -euo pipefail`; checks argument count and each value again
- [ ] Touches only the app folder and its compose project; no prune, no `sudo`
- [ ] Port check before the checkout changes
- [ ] `reset --hard` + `clean -fdx -e .env` + `checkout --detach <sha>`
- [ ] `docker compose -p <project> up -d --build --wait` with a timeout; health check on the published port

### Compose and image
- [ ] Host port and bind address come from env with local defaults
- [ ] A healthcheck exists, so `--wait` means the app answers
- [ ] Bind address fits where the proxy runs

### Tailscale and GitHub (ask the user; Claude can't see them)
- [ ] `tag:ci` grant is port 22 on one host only, with `tests`; no allow-all rule that includes tags
- [ ] Trust credential subject includes the environment
- [ ] Environment limits deployment branches
- [ ] Non-production copy kept out of search engines if it is public
