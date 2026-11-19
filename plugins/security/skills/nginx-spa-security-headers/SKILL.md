---
name: nginx-spa-security-headers
description: Adds security headers (Content-Security-Policy, X-Frame-Options, nosniff, Referrer-Policy, HSTS) to single-page apps or static sites served by nginx, with a CSP derived from what the build actually loads, as an nginx snippet included in every static location. Use when hardening nginx-served React/Vite/static frontends, when a security review flags missing CSP or clickjacking protection on static pages, or when the user asks for nginx security headers.
---

# nginx security headers for static SPAs

Goal: every HTML page and asset nginx serves gets a strict CSP and the standard headers, without breaking the app. The CSP is built from evidence (the build plus runtime hosts), never guessed.

## Workflow

Copy this checklist and work through it:

- [ ] 1. Map the nginx config
- [ ] 2. Audit each build
- [ ] 3. Find runtime hosts
- [ ] 4. Write the snippet
- [ ] 5. Include it in every static location
- [ ] 6. Verify locally
- [ ] 7. Hand over deployment steps

**1. Map the nginx config.** List every `server` and `location`. Mark which locations serve static files (SPA roots, `/assets/`, `alias` sub-apps such as `/admin/`) and which proxy to a backend. The trap: **nginx drops every server-level `add_header` in a location that sets its own `add_header`** (for example `Cache-Control`), so headers must be included per location. Check whether the backend already sends its own CSP (for example helmet): don't include the snippet in that proxy location, because two CSP headers both apply.

**2. Audit each build.** Build the app (`npm run build`), then run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/audit-build.sh" path/to/dist [more/dist ...]
```

It reports inline scripts and event handlers, `eval` / `new Function`, workers, injected `<style>` tags and every external host in the HTML, CSS and JS. A clean result means `script-src 'self'` works. Inline scripts need a hash or nonce, never `'unsafe-inline'` for scripts. Hosts found in JS are often just strings (docs links in error messages): look at the context before allowing them.

**3. Find runtime hosts** that aren't in the build:
- `img-src`: image URLs that come from API data (a CMS, a CDN). Look them up in the database or an API response, and allow that exact host, not `https:`.
- `connect-src`: anything fetched outside the own origin, such as presigned S3 uploads (`https://<bucket>.s3.<region>.amazonaws.com`), analytics or third-party APIs. Search for `fetch(`, `XMLHttpRequest` and `PUT`.
- `frame-src` / `script-src`: embeds (YouTube, Stripe and so on). See [REFERENCE.md](REFERENCE.md).
- Not restricted by CSP: plain navigations (`window.location`, links, OAuth redirects, downloads of presigned URLs).

**4. Write the snippet.** Start from [templates/security-headers.conf](templates/security-headers.conf), fill in the hosts, and document why each host is there, in comments inside the snippet. Keep it in the repo (for example `infra/nginx/<app>-security-headers.conf`) so it's versioned.

**5. Include it** in every static location: `include snippets/<app>-security-headers.conf;`. Remove headers the snippet now sends (such as a repeated `X-Robots-Tag`) from those locations. Leave redirect-only and proxy locations on the server-level headers. If the project has a Docker or dev nginx, include it there too, so local matches production.

**6. Verify locally.**
- Syntax, including configs with Let's Encrypt paths (stub certificates are generated): `bash "${CLAUDE_SKILL_DIR}/scripts/nginx-test.sh" path/to/site.conf path/to/snippet.conf snippets/<app>-security-headers.conf`
- Serve the real build with that config (an `nginx:alpine` container mounting the dist folders), then check: `bash "${CLAUDE_SKILL_DIR}/scripts/check-headers.sh" http://localhost:8099 / /admin/ /admin/some/deep/link /assets/<file>.js @/admin @/api/health`
- Check the root, a deep link (SPA fallback), an asset and an `alias` sub-app. Add redirect and proxied paths with an `@` prefix: they're reported but not failed, since they don't use the snippet.

**7. Hand over deployment steps.** Say plainly what you couldn't test (usually a real browser):
- Copy the snippet to `/etc/nginx/snippets/` and add the `include` lines to the live site file.
- Run `sudo nginx -t && sudo systemctl reload nginx`.
- Use the app with the browser console open, including the flows that reach other hosts (uploads, embeds, payments). A blocked resource is logged there.
- Rollback: comment out the CSP line and reload.
- If step 2 or 3 left doubt, ship `Content-Security-Policy-Report-Only` first and enforce once the console is clean.

## Gotchas

- `always` makes nginx send headers on error responses too (404, 500); keep it.
- HSTS `includeSubDomains` sent from an **apex** domain covers every subdomain. On a subdomain it only covers that subdomain's own subdomains.
- Behind Cloudflare or another CDN, nginx's headers pass through unchanged. If client IPs matter to the backend, see the real-IP section in [REFERENCE.md](REFERENCE.md).
- Vite apps built with a `base` (for example `/admin/`) load assets from `<base>assets/`, which the sub-app's `alias` location serves. It needs the include as well.
