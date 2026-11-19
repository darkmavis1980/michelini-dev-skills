/**
 * Content negotiation for pages: HTML, or the page's Markdown for agents that ask for it.
 * The same rules as the nginx maps (nginx-accept-map.conf), but a real parser, so q-values
 * are exact here. Pure (no framework imports), so middleware, the dev server and tests share it.
 *
 * Source: hawksbaywicklow.com apps/client/src/lib/markdown-negotiation.ts (ADR 0013),
 * itself following michelini.dev ADRs 0009/0010.
 */

export type Representation = 'md' | 'html' | 'none';

export const NOT_ACCEPTABLE_BODY = '406 Not Acceptable: pages are available as text/html or text/markdown.\n';

/**
 * Which representation a page request gets, from its Accept header. Markdown counts only when
 * listed by name (so `*\/*` alone means HTML) and wins ties with HTML, since only agents list it.
 * HTML's q is `text/html`, else `text/*`, else `*\/*`: the most specific wins (RFC 9110).
 * `none` means neither is acceptable, and the caller answers 406.
 */
export function negotiate(accept: string | null | undefined): Representation {
  if (!accept?.trim()) return 'html';
  const q = new Map<string, number>();
  for (const part of accept.toLowerCase().split(',')) {
    const [type, ...params] = part.split(';').map((s) => s.trim());
    const qParam = params.find((p) => /^q\s*=/.test(p));
    const value = qParam ? Number(qParam.split('=')[1]) : 1;
    if (type && !q.has(type)) q.set(type, Number.isFinite(value) ? value : 0);
  }
  const md = q.get('text/markdown') ?? 0;
  const html = q.get('text/html') ?? q.get('text/*') ?? q.get('*/*') ?? 0;
  if (md <= 0 && html <= 0) return 'none';
  return md > 0 && md >= html ? 'md' : 'html';
}

/** The `.md` twin of a site path, keeping any query: `/` → `/index.md`, `/a/b/?x=1` → `/a/b.md?x=1`. */
export function markdownPath(path: string): string {
  const [pathname, query] = path.split(/\?(.*)/s, 2);
  const md = pathname === '/' || pathname === '' ? '/index.md' : `${pathname.replace(/\/+$/, '')}.md`;
  return query ? `${md}?${query}` : md;
}

/** The page path a `.md` URL stands for: `/index.md` → `/`, `/a/b.md` → `/a/b`. */
export function pagePathFromMarkdown(pathname: string): string {
  const page = pathname.replace(/\.md$/, '');
  return page === '/index' || page === '' ? '/' : page;
}

/** True for page URLs (no file extension). Files, feeds and assets are never negotiated. */
export function isPagePath(pathname: string): boolean {
  return !/\.[A-Za-z0-9]+$/.test(pathname);
}
