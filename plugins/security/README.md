# security

Security hardening skills for web apps and the servers that host them.

## Skills

| Skill | What it does |
| --- | --- |
| `nginx-spa-security-headers` | Adds CSP, X-Frame-Options, nosniff, Referrer-Policy and HSTS to SPAs/static sites served by nginx, deriving the CSP from what the build actually loads. Includes scripts to audit a build, `nginx -t` a config in Docker, and check headers on live paths. |

Requires `bash`, `curl`, and Docker + `openssl` for the nginx syntax check.

## Install

```
/plugin install security@michelini-dev-skills
```
