# Markdown for agents: reference

## Where this comes from

Three production sites by the same author:

| Site | Stack | Decision records |
|---|---|---|
| michelini.dev | Vite SPA, static files, nginx maps, builders from data + Markdown posts, Vite dev middleware | ADR 0009 (serve Markdown to agents), ADR 0010 (q-values and 406) |
| homebattery.ie | react-router SSG + nginx maps, turndown over the prerendered HTML | follows michelini.dev 0009/0010 |
| hawksbaywicklow.com | Next.js 16 SSR, `proxy.ts` + `/md-export` route handler, builders over live API data | ADR 0013 |

Options the ADRs rejected, so the question doesn't come up again:
- **Cloudflare's edge HTML-to-Markdown** converts whatever HTML it gets. For a client-rendered SPA that's the empty shell.
- **njs or a Node proxy for exact q-values in nginx** adds a module or a process to run for a static site. The first-decimal limit doesn't matter in practice.
- **Substring match on `text/markdown`** (no q-values) gives Markdown to `text/html, text/markdown;q=0.1`, where HTML is preferred. acceptmarkdown.com flags it.

## Negotiation table

What every implementation must return. `negotiate.test.ts` and `check-markdown.sh` both cover these.

| Accept | Result |
|---|---|
| browser default (`text/html,…,*/*;q=0.8`) | html |
| `*/*` | html |
| (none) or empty | html |
| `text/markdown` | md |
| `text/markdown, text/html;q=0.9` | md |
| `text/markdown, */*` | md (tie: Markdown wins) |
| `text/html;q=0.5, text/markdown;q=0.5` | md (tie) |
| `text/html, text/markdown;q=0.1` | html |
| `text/html;q=0.2, text/*, text/markdown;q=0.5` | md (text/html is the most specific HTML match, q 0.2) |
| `text/*;q=0.9, text/markdown;q=0.5` | html |
| `text/markdown;q=0` | none → 406 |
| `text/markdown;q=0, text/html` | html |
| `application/json` | none → 406 |
| `application/x-content-negotiation-probe` | none → 406 |

The nginx maps return the same results, except that two q-values with the same first decimal (0.85 vs 0.8) count as a tie and go to Markdown.

## Document shape

Every Markdown page, whichever way it's produced:

```markdown
# <Page title, without the " — Site name" suffix>

> <One-sentence summary: the meta description>

- <Short facts: date, author, location, price, tags… only what the page has>
- Web page: https://<domain>/<path>

---

<Body: headings from ## down, lists, tables, links>

<Optional site footer line, e.g. an independence or copyright notice the HTML footer carries>
```

- **Absolute URLs** for every link and image, so they resolve outside the site.
- **Links between pages point at the `.md` twins** (`https://<domain>/docs/setup.md`), so an agent stays in Markdown. Links to files, external sites and anchors stay as they are. The turndown script makes links absolute but leaves them pointing at the HTML. Rewrite internal page links to `.md` there too if the site has a closed set of page routes.
- **Index pages list their items** with a link to each item's `.md` and a one-line summary. They show the whole list, not one paginated page (cap it as a guard).
- **No UI text**: no buttons, nav, cookie banners, form controls, `aria-hidden` decorations, or "click here".
- **Dates as words** in the site's time zone (`19 November 2026`), not ISO strings or relative "2 days ago".
- **Builders are pure** (`(records) => string`): no fetching, no framework imports. Tests then need no mocks.
- Index pages must not fail when the API is down: render an empty list. Detail pages treat any fetch failure as "no such page" (404).

## llms.txt

`/llms.txt` (served as `text/markdown`) is the map for agents. Point its links at the `.md` URLs. Otherwise an agent that follows them from a client-rendered SPA gets the empty shell. Add one line saying the site negotiates: "Every page is also served as Markdown when the request sends `Accept: text/markdown`."

## Caching and CDNs

- `Vary: Accept` tells caches to keep the two versions apart. Some CDNs ignore `Vary` and cache by URL only.
- Cloudflare doesn't cache extensionless HTML or `.md` by default, so the default setup is safe. If someone adds a "Cache Everything" rule, it must bypass page routes (simplest), or add `Accept` to the cache key where the plan allows custom cache keys. Otherwise the first visitor's version is served to everyone.
- `Cache-Control: no-cache` on pages and `.md` files. Hashed assets stay `immutable`.
- Leave any CDN-side HTML-to-Markdown conversion off for these routes. The site already answers, and an edge conversion of an SPA converts the empty shell.

## SEO

- `.md` URLs send `X-Robots-Tag: noindex` so search engines don't index them as duplicates. The nginx template does this.
- The HTML stays the canonical page. Don't add `.md` URLs to `sitemap.xml`.
- `rel="alternate" type="text/markdown"` in the page `<head>` is fine for SEO and helps agents find the Markdown.

## Testing checklist

- [ ] Parser tests pass (`negotiate.test.ts`), plus tests for the project's route list (which paths have Markdown)
- [ ] `check-markdown.sh <base> <content paths…>` passes against Docker or a preview build
- [ ] A non-content route (`/login`) still returns HTML for `Accept: text/markdown`, and its `.md` is a 404
- [ ] In-app navigation still works (Next.js: the RSC requests aren't 406)
- [ ] `/llms.txt` links resolve to Markdown
- [ ] Production nginx: `nginx -t` passes on the server after the map include is added to `http {}`
