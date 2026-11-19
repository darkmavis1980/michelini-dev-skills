# security

Security hardening skills for web apps and the servers that host them.

## Skills

| Skill | What it does |
| --- | --- |
| `nginx-spa-security-headers` | Adds CSP, X-Frame-Options, nosniff, Referrer-Policy and HSTS to SPAs/static sites served by nginx, deriving the CSP from what the build actually loads. Includes scripts to audit a build, `nginx -t` a config in Docker, and check headers on live paths. |
| `deployment-audit` | Audits a live site from the outside with read-only requests (TLS, redirect, headers, exposed `.git` / `.env` / source maps, directory listing, cookies, CORS, protected routes, CDN caching, Cloudflare implications), then reviews the repo's deployment files and writes a dated report. `scripts/probe.sh` does the probing and never prints the content of an exposed file. |

Requires `bash`, `curl` and `openssl`; Docker for the nginx syntax check; `dig` and `python3` (optional) for the deployment audit's CDN detection.

## Install

```
/plugin install security@michelini-dev-skills
```
