// src/app/md-export/[[...path]]/route.ts
// The Markdown version of a page. Never linked: proxy.ts rewrites a page request here when its
// Accept header prefers text/markdown, or when the URL ends in .md, and it turns direct requests
// for /md-export/... into 404s. The segments are the page's own: /docs/setup arrives as
// ['docs', 'setup'], the home page as none.
//
// Source: hawksbaywicklow.com apps/client/src/app/md-export/[[...path]]/route.ts (ADR 0013).

// Builders are pure functions in src/lib/markdown-pages.ts: they take the same records the HTML
// page renders and return a Markdown document (see REFERENCE.md, "Document shape").
import { homeMarkdown, sectionIndexMarkdown, itemMarkdown } from '@/lib/markdown-pages';
import { getHome, getSection, getItem } from '@/lib/api';

const HEADERS = {
  'Content-Type': 'text/markdown; charset=utf-8',
  Vary: 'Accept',
  'Cache-Control': 'no-cache',
};

// Index pages must never take the request down: an unreachable API yields an empty list.
async function safe<T>(promise: Promise<T>, fallback: T): Promise<T> {
  try {
    return await promise;
  } catch {
    return fallback;
  }
}

// Detail pages: any API failure (mostly a 404 for an unknown slug) means "no such page".
async function maybe<T>(promise: Promise<T>): Promise<T | null> {
  try {
    return await promise;
  } catch {
    return null;
  }
}

async function render(segments: string[], query: URLSearchParams): Promise<string | null> {
  const [section, slug] = segments;
  if (!section) return homeMarkdown(await safe(getHome(), { items: [] }));
  if (!slug) return sectionIndexMarkdown(section, await safe(getSection(section, query), []));
  const item = await maybe(getItem(section, slug));
  return item ? itemMarkdown(section, item) : null;
}

export async function GET(request: Request, { params }: { params: Promise<{ path?: string[] }> }) {
  const { path = [] } = await params;
  const markdown = await render(path, new URL(request.url).searchParams);
  if (markdown === null) {
    return new Response('# Not found\n\nThere is no page at this address.\n', { status: 404, headers: HEADERS });
  }
  return new Response(markdown, { headers: HEADERS });
}
