# Reference: reading the probe and fixing what it finds

Severities are a starting point. Raise or lower them for the app: an exposed `.env` on a site with real credentials is critical, while a missing `Referrer-Policy` on a brochure site is minor.

## TLS

| Result | Meaning | Fix |
| --- | --- | --- |
| TLS 1.0 / 1.1 accepted | Old protocols with known weaknesses | nginx: `ssl_protocols TLSv1.2 TLSv1.3;`. Behind Cloudflare: SSL/TLS → Edge Certificates → Minimum TLS Version 1.2 |
| Certificate expires in under 14 days | Renewal is probably broken | `sudo certbot renew --dry-run`, `systemctl list-timers \| grep certbot` |
| The issuer is a CDN (Google Trust Services, Cloudflare, Amazon) | The edge certificate. The origin's own certificate isn't visible from outside | Check the origin certificate and the CDN's origin TLS mode (below) |

## Redirect

- **Plain HTTP answers 200:** add a port-80 server block that only returns `301 https://$host$request_uri`. Behind Cloudflare, "Always Use HTTPS" also works.
- **302 / 307:** use 301 or 308, so browsers and search engines remember the redirect.

## Security headers

- **Missing on pages:** clickjacking and no CSP as a second line of defence. Use the `nginx-spa-security-headers` skill. For server-rendered apps, the framework's middleware (helmet for Express, `headers()` in Next.js) works too.
- **Missing on assets only:** lower risk. `nosniff` matters most there. Usually a location with its own `add_header` (such as `Cache-Control`) that doesn't include the snippet.
- **CDN-cached copy lacks headers, origin has them:** the CDN cached the file before the headers were added. Purge the cache, or wait for the next build if file names are hashed.
- **CSP with `'unsafe-inline'` / `'unsafe-eval'` in `script-src`:** this removes most of the CSP's protection against XSS. Find the inline script or `eval` user. A hash or nonce can replace `'unsafe-inline'`.
- **HSTS max-age under 180 days:** use `max-age=31536000`. Add `includeSubDomains` only if every subdomain serves HTTPS. Sent from an apex domain, it covers all of them.
- **`Server` version / `X-Powered-By`:** small information leaks. nginx: `server_tokens off;`. Express: `app.disable('x-powered-by')`.

## Exposed files

- **`.git/*` served:** the whole source history, often with secrets, can be downloaded. **Critical.** Serve only the build folder (`root .../dist`). Never use the repo root as the web root. As a guard: `location ~ /\. { deny all; }` (keep `/.well-known/` allowed for ACME challenges).
- **`.env`, dumps, configs served:** **critical**. Remove them from the web root and rotate every secret they contained, because they may already have been fetched.
- **Source map served:** exposes the original source and comments. Not a vulnerability in itself, but turn it off for production builds (Vite `build.sourcemap: false`, the default) unless it's intentional.
- **Directory listing:** nginx `autoindex off;` (the default). Find the `autoindex on`.
- The probe treats responses identical to the app's fallback page as safe, since SPAs answer every path with `index.html`.

## Cookies

The probe only sees cookies set without a session. Check sign-in cookies in the code:
- `Secure`, `HttpOnly` and `SameSite=Lax` (or `Strict`);
- ideally the `__Host-` prefix, which forces `Secure`, `Path=/` and no `Domain`.

Cookies without `HttpOnly` are fine only when JavaScript has to read them, and they must never hold a session.

## CORS

- **Any origin reflected with `Allow-Credentials: true`:** **critical**. Any site can read a signed-in user's API responses. Allow an explicit list of origins.
- **Any origin reflected without credentials, or `*`:** fine for public data only.

## Protected paths

- **200 without a session:** **critical** if it returns data. Check whether the auth middleware is mounted before the route.
- **Served from the CDN cache (`HIT`):** the CDN may be serving one user's response to others. Send `Cache-Control: private, no-store` on personal responses, and remove any "cache everything" rule covering the API.

## Behind a CDN (Cloudflare and others)

Work through these whenever the probe reports a CDN:

1. **Client IPs.** The origin sees the CDN's addresses. Rate limits and IP logs then lump visitors together: one person can exhaust a per-IP sign-in limit for everyone on the same edge. **Check:** look at IPs in the app's logs or records. **Fix** (Cloudflare + nginx): trust only Cloudflare's ranges, in `http` context:
   ```bash
   { curl -s https://www.cloudflare.com/ips-v4; echo; curl -s https://www.cloudflare.com/ips-v6; echo; } \
     | grep -v '^$' | sed 's/^/set_real_ip_from /; s/$/;/' > cloudflare-real-ip.conf
   echo 'real_ip_header CF-Connecting-IP;' >> cloudflare-real-ip.conf
   sudo cp cloudflare-real-ip.conf /etc/nginx/conf.d/ && sudo nginx -t && sudo systemctl reload nginx
   ```
2. **The origin reachable directly.** If the app port is open on the server's public IP, attackers can skip the CDN and the proxy. **Check:** `ss -ltnp` on the server shows the app on `127.0.0.1`, not `0.0.0.0` or `*`. **Fix:** bind the app to `127.0.0.1` and firewall the app port.
3. **CDN-to-origin TLS.** Cloudflare's "Flexible" mode sends plain HTTP to the origin, and "Full" accepts any certificate. Use **Full (strict)** with a valid origin certificate. The SSL/TLS Overview setting is **zone-wide**: use a Configuration Rule for one hostname, or check every proxied subdomain first. With strict mode, an expired origin certificate means downtime (error 526), so check that renewal works.
4. **Caching of personal data.** Cloudflare caches some file extensions by default (`.csv`, `.pdf`, `.json` is not one of them) unless the response says otherwise. Personal downloads and exports need `Cache-Control: no-store`. Check `cf-cache-status` on such responses: `BYPASS` or `DYNAMIC` is good.
5. **The privacy policy.** The CDN sees every request decrypted, including IPs and cookies. Name it as a processor, with its transfer mechanism (for Cloudflare: the EU–US Data Privacy Framework and SCCs, to be confirmed against its current DPA), and list any security cookies it may set (such as `__cf_bm`).
6. **Injected scripts.** Rocket Loader, Email Obfuscation, automatic Web Analytics and some bot detection add scripts that a strict CSP blocks. Turn them off for the hostname, or allow them deliberately.

## Server-side checks to hand the user

Only the server can show these. List the relevant ones under "Not covered" or as **Check** lines:
- `ss -ltnp`: the app listens on `127.0.0.1`, and Postgres or Redis on localhost only.
- the firewall (`ufw status`, `nft list ruleset`): only 22, 80 and 443 open.
- `ps -o user= -p $(pgrep -f <app>)`: the app doesn't run as root.
- backups: a scheduled run, encryption and retention at the destination, one tested restore.
- `sudo certbot renew --dry-run`.
- OS security updates (`unattended-upgrades`), and SSH with keys only, no root login.
