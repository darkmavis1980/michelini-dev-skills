---
name: markdown-for-agents
description: Serve every page of a website as Markdown to AI agents and LLM clients — the same URL returns Markdown when the request's Accept header prefers text/markdown (with q-values, ties to Markdown, 406 when nothing fits, Vary: Accept), plus a .md twin at every page URL (/ → /index.md, /x → /x.md) and llms.txt links to them. Covers static SPAs and prerendered sites behind nginx (map blocks, no njs), Next.js (proxy/middleware rewrite to a route handler), Express, the Vite dev server, and generating the Markdown (convert prerendered HTML with turndown, or write builders from the page data). Use this whenever the user wants to "serve markdown to agents", "support Accept: text/markdown", "content negotiation for markdown", "make the site agent-readable / LLM-friendly", add .md versions of pages, improve an acceptmarkdown.com score, or fix llms.txt links that point at an empty SPA shell.
---

# Markdown for agents

One URL, two representations: browsers get HTML, agents that ask for `text/markdown` get the page's Markdown. Every page also has a `.md` twin that always returns Markdown.

## The rules (same on every stack)

1. **Markdown only when named.** `text/markdown` must appear in `Accept`. `*/*` alone (curl, most libraries) means HTML.
2. **HTML's q** is `text/html`, else `text/*`, else `*/*`. The most specific one wins (RFC 9110). No `Accept` header means HTML.
3. **Markdown wins ties**, because only agents list it. HTML wins only with a strictly higher q.
4. **Neither acceptable → 406** with a plain-text body naming both types: `406 Not Acceptable: pages are available as text/html or text/markdown.` This applies to page URLs only. Files and assets are never negotiated.
5. **`.md` twins**: `/` → `/index.md`, `/a/b` and `/a/b/` → `/a/b.md`. The query is kept. A page with no Markdown version falls back to HTML. Its `.md` URL is a 404.
6. **`Vary: Accept`** on every page response (HTML, Markdown, 406) so no cache gives one client the other's version. Also `Cache-Control: no-cache` on pages.
7. **Missing files are real 404s**, never the HTML shell with a 200.
8. **Discoverability**: `/llms.txt` links to the `.md` URLs. Where pages are rendered (SSR/SSG), add `<link rel="alternate" type="text/markdown" href="/x.md">`.

Browsers never send `text/markdown`, so people see no change.

## Pick the serving layer

| Site | Where to negotiate | Templates |
|---|---|---|
| Static SPA or prerendered (SSG) files behind nginx | nginx `map` blocks pick `/x.md` from disk | [nginx-accept-map.conf](templates/nginx-accept-map.conf) (http context) + [nginx-locations.conf](templates/nginx-locations.conf) (variant A: SPA shell, B: prerendered) |
| Next.js, pages rendered per request | `proxy.ts` (Next 16; `middleware.ts` before) rewrites to an internal route handler | [next-proxy.ts](templates/next-proxy.ts) + [next-md-route.ts](templates/next-md-route.ts) |
| Express renders HTML | Middleware before the HTML routes | [express-markdown.ts](templates/express-markdown.ts) |
| Vite dev server (for the nginx setup) | Dev middleware that applies the same rules | [vite-markdown-dev.ts](templates/vite-markdown-dev.ts) |

Every JS/TS variant shares [negotiate.ts](templates/negotiate.ts), the parser, and its tests [negotiate.test.ts](templates/negotiate.test.ts). The nginx maps compare q-values only to the first decimal (0.85 and 0.8 tie). This is a known and accepted limit: clients don't send values that fine, and it avoids njs. Copy the map file as it is. Don't "fix" it with njs or a Node proxy unless the user asks.

## Pick the Markdown source

| Source | When | How |
|---|---|---|
| **Convert the prerendered HTML** | The build already emits HTML per route (SSG). | [html-to-markdown.mjs](templates/html-to-markdown.mjs) after the build: turndown over `<main>`, title and description from `<head>`. It can't drift from the site. |
| **Builders from the page data** | Client-rendered SPA (the HTML is an empty shell), or content in data files or Markdown. | Pure functions `(data) => string` next to the data, emitted at build time (and served by the Vite dev plugin). |
| **Builders at request time** | Pages render from live API data (Next/Express SSR). | The same pure builders, called from the route handler or middleware with the same records the HTML page uses. |

All three produce the same document shape. See [REFERENCE.md](REFERENCE.md#document-shape).

## Workflow

1. Read the repo: framework and rendering mode, the production nginx config (and the Docker one), how routes are listed, what `llms.txt` contains, and whether the client app already has a test runner.
2. Decide which routes get Markdown. Content pages do. Interactive or private ones (login, search, forms, account, admin) don't, and must fall back to HTML.
3. Add the serving layer and the Markdown source from the templates. Replace the `<placeholders>`, and keep the source comments so the next reader knows where they came from.
4. Add the parser tests to the client's test suite, plus tests for the project's own route list (`markdownSegments` or similar).
5. Update `/llms.txt` to link to the `.md` URLs, and add `rel="alternate"` links where pages are rendered.
6. If the repo keeps ADRs, write one for the decision. The rules above are the decision. Link to it from the code comments.
7. Verify against a running site (Docker or `vite preview` behind nginx; the Vite dev server only if it has the dev plugin):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/markdown-for-agents/scripts/check-markdown.sh" http://localhost:8079 / /help /blog/some-post
   ```
   It checks every rule above per path, exits 1 on a failure, and is read-only. Pass the paths that should have Markdown. A path with no `.md` file fails the Markdown checks, which is correct for content pages.
8. Tell the user what production needs. nginx: the `map` include goes in the **http** context on the server, plus the changed `location` blocks. CDN: the caching note in REFERENCE.md.

## Traps

- **Next.js client navigations** send `RSC: 1` and `Accept: text/x-component`. Server Actions are POSTs. Both must skip negotiation, or every in-app navigation becomes a 406.
- **Next replaces `Vary`** on rendered pages. Set `Vary: Accept` for HTML at the reverse proxy (`add_header Vary Accept always;`).
- **`try_files $uri/`** with `.md` files in a folder (`dist/blog/x.md`) turns `/blog` into a 301 to `/blog/`. Variant A leaves `$uri/` out on purpose.
- **`add_header` in a location** drops every server-level `add_header`. Include the security-headers snippet in each location (see `security:nginx-spa-security-headers`).
- **`map` inside `server {}`** is an nginx error. It must be in `http {}` (in `conf.d/*.conf`, at the top of the file, outside `server`).
