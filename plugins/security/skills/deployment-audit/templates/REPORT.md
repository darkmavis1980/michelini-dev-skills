# Security review: production deployment

- **Date:** YYYY-MM-DD
- **Scope:** the live site `https://<host>` and the deployment files in the repo (<list: nginx config, process manager config, deploy and backup scripts, IAM / bucket policies>).
- **Method:** read-only requests to the live site from outside (TLS, headers, redirects, exposed paths, auth on protected routes, caching), plus a read of the deployment files. The server's own config, firewall and any CDN dashboard were not visible; where they might differ from the repo, the check is listed for the user.

<One paragraph on the architecture as observed, e.g. "The site is behind Cloudflare: DNS points at Cloudflare and visitors get Cloudflare's edge certificate." Say which findings follow from it.>

## Blockers found along the way (not security)

<Functional problems noticed while probing, e.g. a public endpoint returning 404. Delete this section if there are none.>

## Findings

### 1. <Short title> (<critical | high | medium | low>[, needs confirming])

<What was observed, with the evidence (status codes, header values, file and line references). Never paste secret values.>

<What an attacker or a visitor could do because of it, concretely.>

**Check:** <how the user confirms it, if it couldn't be confirmed from outside.>

**Fix:** <the concrete change, with a config snippet where useful.>

<!-- When fixed later, add:  **Status (YYYY-MM-DD): fixed.** <what changed, how it was verified> -->

## What holds up

| Area | Result |
| --- | --- |
| TLS | <versions offered / refused, certificate expiry> |
| HTTP → HTTPS | <status, same path and query> |
| Exposed files | <what was tried, what came back> |
| Protected routes without a session | <status codes> |
| <…> | <…> |

## Not covered

- <Server-side checks only the user can do: listening ports, firewall, process user, backups, OS updates, SSH.>
- <Dashboards: CDN, cloud console.>
- <A browser test of the main flows, if not done.>
