---
name: deployment-audit
description: Audits a live, deployed website or web app from the outside with read-only requests (TLS, HTTP→HTTPS redirect, security headers, exposed files such as .git/.env/source maps, directory listing, cookies, CORS, auth on admin routes, CDN caching and Cloudflare implications), then reviews the repo's deployment files (nginx, PM2/systemd, Docker, deploy and backup scripts, cloud IAM) and writes a dated report. Use when the user asks for a deployment or production security review, a pre-launch check, "is my site secure", or after deploying something new to a server.
---

# Deployment audit

Finds what a code review can't see: how the site actually behaves in production. All probes are read-only (GET / HEAD / OPTIONS, about 60 requests).

## Ground rules

- **Only audit sites the user owns or is authorised to test.** If that's unclear, ask before probing. No fuzzing, brute force, login attempts or load.
- **Never print secrets.** If something like `.env` is exposed, report that it is served and how big it is, never its content. Don't print values from local `.env` files either.
- Facts you couldn't observe (the server's firewall, a CDN dashboard) become **checks for the user**, never assumptions.

## Workflow

- [ ] 1. Gather the targets
- [ ] 2. Run the probe
- [ ] 3. Dig into anything odd
- [ ] 4. Read the deployment files
- [ ] 5. Draw the CDN conclusions
- [ ] 6. Write the report

**1. Gather the targets.** Take from the user or the repo:
- the public URL;
- one public API path (a health endpoint is ideal);
- a few paths that must need a session (admin and account APIs);
- any app-specific files that must never be served.

**2. Run the probe:**

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/probe.sh" https://example.com \
  --api /api/health --protected /api/admin/users --protected /api/me [--extra /uploads/private/]
```

Every line starts with PASS, WARN, FAIL or INFO. [REFERENCE.md](REFERENCE.md) explains each result and its fix. For staging with a self-signed certificate, add `--insecure`.

**3. Dig into anything odd** with single `curl -sI` requests before reporting it. Typical cases:
- An asset lacks headers only in the CDN cache (the probe already re-asks the origin).
- A public API returns 404 when it should return data, which is a functional blocker worth reporting.
- A redirect goes somewhere unexpected.

Report functional problems you notice too, clearly separated from security findings.

**4. Read the deployment files** in the repo, for things the outside can't show:
- **The app's listen address.** It should be `127.0.0.1` behind a proxy. Binding to all interfaces lets anyone skip the proxy and forge `X-Forwarded-For`.
- **The proxy trust setting** (for example Express `trust proxy`) against the real number of proxies in front of the app.
- **Each reverse-proxy location's headers.** nginx drops server-level `add_header` lines in any location that has its own.
- **Deploy scripts:** stop/start ordering, failure handling, and secrets passed on command lines.
- **Backup scripts:** file permissions (`umask`), where dumps are written, and encryption and retention at the destination.
- **IAM and bucket policies:** least privilege, and no public access.
- **Config samples:** secrets committed by mistake.

**5. Draw the CDN conclusions.** If the probe reports a CDN (usually Cloudflare), work through the "Behind a CDN" checklist in [REFERENCE.md](REFERENCE.md):
- client IPs;
- the CDN-to-origin TLS mode, and whether it's zone-wide;
- caching of personal responses;
- whether the privacy policy names the CDN;
- features that inject scripts.

**6. Write the report** from [templates/REPORT.md](templates/REPORT.md) into the repo's review folder, for example `docs/reviews/YYYY-MM-DD-security-review-deployment.md`. Rank findings by severity. For each, give:
- the evidence;
- a **Check** for anything unconfirmed;
- a concrete **Fix**, with config snippets.

Then list "What holds up" and "Not covered". In the chat, summarise the findings and say which ones need the user (server shell, dashboards). Add a **Status** line under a finding when it's fixed later.

## Related

- Missing CSP or other headers on static pages: the `nginx-spa-security-headers` skill in this plugin builds the snippet from the build's real needs.
- Code-level issues: `/security-review` covers the code diff. This skill covers the running deployment.
