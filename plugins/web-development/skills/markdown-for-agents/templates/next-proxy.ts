// src/proxy.ts (Next.js 16+). On Next 15 and earlier the file is src/middleware.ts and the
// function is named `middleware`; the body is the same.
//
// - `/x.md` (and `/index.md` for home) always gets the Markdown.
// - A page URL gets the Markdown when its Accept header prefers text/markdown, HTML when it
//   prefers HTML (browsers, curl), and 406 when it accepts neither.
// - Pages with no Markdown version keep serving HTML.
//
// Source: hawksbaywicklow.com apps/client/src/proxy.ts (ADR 0013).
import { NextResponse, type NextRequest } from 'next/server';
import { NOT_ACCEPTABLE_BODY, negotiate } from '@/lib/negotiate';
import { MARKDOWN_ROUTE, markdownSegments } from '@/lib/markdown-routes';

export function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;

  // The internal route is reachable only through the rewrite below.
  if (pathname === MARKDOWN_ROUTE || pathname.startsWith(`${MARKDOWN_ROUTE}/`)) {
    return new NextResponse('Not found\n', { status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }

  const isMdUrl = pathname.endsWith('.md');
  // Other files (feeds, icons, images) are not pages: leave them alone.
  if (!isMdUrl && /\.[A-Za-z0-9]+$/.test(pathname)) return NextResponse.next();

  const segments = markdownSegments(pathname);
  if (isMdUrl) {
    if (!segments) return NextResponse.next(); // unknown .md → the normal 404
    return rewriteToMarkdown(request, segments, search);
  }

  // Only negotiate plain page loads. Next's client navigations (RSC header) and Server Actions
  // send their own Accept (text/x-component), which would otherwise read as a 406.
  const isPageLoad = (request.method === 'GET' || request.method === 'HEAD') && !request.headers.has('rsc');
  const representation = isPageLoad ? negotiate(request.headers.get('accept')) : 'html';
  if (representation === 'none') {
    return new NextResponse(NOT_ACCEPTABLE_BODY, {
      status: 406,
      headers: { 'Content-Type': 'text/plain; charset=utf-8', Vary: 'Accept' },
    });
  }
  if (representation === 'md' && segments) return rewriteToMarkdown(request, segments, search);

  // HTML. Next replaces any Vary set here with its own on rendered pages, so `Vary: Accept` on
  // HTML has to come from the reverse proxy in production: in nginx, `add_header Vary Accept always;`
  // in the location that proxies to Next.
  return NextResponse.next();
}

function rewriteToMarkdown(request: NextRequest, segments: string[], search: string) {
  const url = request.nextUrl.clone();
  url.pathname = [MARKDOWN_ROUTE, ...segments.map(encodeURIComponent)].join('/');
  url.search = search;
  return NextResponse.rewrite(url);
}

export const config = {
  // Skip the API proxy, Next's own assets, prefetches and generated metadata files.
  matcher: [
    {
      source: '/((?!api/|_next/|icon|apple-icon|manifest|sitemap|robots|images/).*)',
      missing: [{ type: 'header', key: 'next-router-prefetch' }],
    },
  ],
};

// ---- src/lib/markdown-routes.ts ------------------------------------------------------------
// Which site paths have a Markdown version. Project-specific: list your sections and the
// routes that are interactive or hand-built (no Markdown), and keep it in step with the routes.
//
// export const MARKDOWN_ROUTE = '/md-export'; // internal, never linked
// const SECTIONS = new Set(['docs', 'news']);              // index + one page per item
// const NO_MARKDOWN = new Set(['login', 'search', 'api', MARKDOWN_ROUTE.slice(1)]);
//
// /** Path segments of the Markdown page for a site path or its .md twin; null when it has none. */
// export function markdownSegments(pathname: string): string[] | null {
//   let clean: string;
//   try { clean = decodeURIComponent(pathname); } catch { return null; }
//   clean = clean.replace(/\/+$/, '').replace(/\.md$/, '');
//   const segments = clean.split('/').filter(Boolean);
//   if (segments.length === 0 || (segments.length === 1 && segments[0] === 'index')) return [];
//   if (segments.some((s) => s.includes('.'))) return null;
//   const first = segments[0];
//   if (SECTIONS.has(first)) return segments.length <= 2 ? segments : null;
//   if (segments.length === 1 && !NO_MARKDOWN.has(first)) return segments;
//   return null;
// }
