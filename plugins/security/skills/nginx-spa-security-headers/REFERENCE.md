# Reference

## Common third-party CSP additions

Add only what the audit or the code shows is used. Check the provider's current docs, because these lists change.

| Service | Directives to add |
| --- | --- |
| Google Fonts | `style-src https://fonts.googleapis.com`; `font-src https://fonts.gstatic.com` |
| Stripe.js / Elements | `script-src https://js.stripe.com`; `frame-src https://js.stripe.com https://hooks.stripe.com`; `connect-src https://api.stripe.com` |
| Google Analytics 4 (gtag) | `script-src https://www.googletagmanager.com`; `connect-src https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com`; `img-src https://*.google-analytics.com https://*.googletagmanager.com` |
| Cloudflare Web Analytics | `script-src https://static.cloudflareinsights.com`; `connect-src https://cloudflareinsights.com` |
| Cloudflare Turnstile | `script-src https://challenges.cloudflare.com`; `frame-src https://challenges.cloudflare.com` |
| YouTube embeds | `frame-src https://www.youtube-nocookie.com https://www.youtube.com` |
| Vimeo embeds | `frame-src https://player.vimeo.com` |
| Sentry | `connect-src https://*.ingest.sentry.io` (or the region's ingest host, e.g. `*.ingest.de.sentry.io`) |
| Presigned S3 uploads | `connect-src https://<bucket>.s3.<region>.amazonaws.com` (virtual-hosted style; path style is `https://s3.<region>.amazonaws.com`) |

Adding `frame-src` for an embed doesn't relax `frame-ancestors 'none'`: one controls what the page embeds, the other who can embed the page.

## Cloudflare features that inject scripts

A strict `script-src 'self'` blocks scripts Cloudflare adds at the edge: Rocket Loader, Email Address Obfuscation, automatic Web Analytics injection, and some bot-detection JavaScript. If the site is proxied by Cloudflare and the console shows blocked `cdn-cgi` or `cloudflareinsights` scripts, either turn that feature off for the hostname or allow the script explicitly.

## Report-only rollout

If the audit leaves doubt, change the header name to `Content-Security-Policy-Report-Only`, keeping the same value. Browsers then log violations to the console but block nothing. Use every flow, then switch to the enforcing name. Don't send both with different values by accident: the enforcing one still applies.

## Hashes for an unavoidable inline script

Instead of `'unsafe-inline'`, allow that exact script:

```bash
printf '%s' 'console.log("inline")' | openssl dgst -sha256 -binary | openssl base64
# → add 'sha256-<output>' to script-src
```

The hash must match the script's content byte for byte, between the tags, so recompute it whenever the build changes it.

## Real client IPs behind Cloudflare

Behind Cloudflare, nginx's `$remote_addr` is a Cloudflare edge address. Backends that rate-limit or log by IP (via `X-Real-IP` / `X-Forwarded-For`) then see Cloudflare instead of visitors. To restore the visitor's address, trust only Cloudflare's ranges:

```bash
# generate the include from the live lists (re-run when Cloudflare updates them)
{ curl -s https://www.cloudflare.com/ips-v4; echo; curl -s https://www.cloudflare.com/ips-v6; echo; } \
  | grep -v '^$' | sed 's/^/set_real_ip_from /; s/$/;/' > cloudflare-real-ip.conf
echo 'real_ip_header CF-Connecting-IP;' >> cloudflare-real-ip.conf
sudo cp cloudflare-real-ip.conf /etc/nginx/conf.d/
```

It's in `http` context (`conf.d/`), so it applies to every site on the server, which is correct when they're all behind Cloudflare. Check afterwards that the access log shows visitors' addresses.

Related: the backend should listen on `127.0.0.1` only, so nobody can reach it directly and forge `X-Forwarded-For`. Set Cloudflare's SSL mode to **Full (strict)** when the server has a valid certificate. The SSL/TLS Overview setting is zone-wide, so a Configuration Rule can scope it to one hostname.
