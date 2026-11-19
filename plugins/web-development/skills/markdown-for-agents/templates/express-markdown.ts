// Express middleware: serve a page's Markdown when the Accept header prefers it, or when the
// URL is the page's .md twin. For apps that render HTML at request time in Express (or proxy
// to something that does). Static sites use the nginx maps instead.
//
// Mount it before the HTML routes and after the API router:
//   app.use('/api', apiRouter);
//   app.use(markdownNegotiation({ render: renderMarkdown }));
//   app.get('*', renderHtml);
import type { Request, Response, NextFunction, RequestHandler } from 'express';
import { NOT_ACCEPTABLE_BODY, isPagePath, negotiate, pagePathFromMarkdown } from './negotiate.js';

export interface MarkdownOptions {
  /** Markdown for a page path ('/', '/docs/setup'), or null when the page has no Markdown version. */
  render: (pagePath: string, query: URLSearchParams) => Promise<string | null>;
}

export function markdownNegotiation({ render }: MarkdownOptions): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') return next();
    const isMdUrl = req.path.endsWith('.md');
    if (!isMdUrl && !isPagePath(req.path)) return next(); // files, feeds, assets

    try {
      // Every page response varies on Accept, the HTML ones too.
      res.vary('Accept');

      const representation = isMdUrl ? 'md' : negotiate(req.get('accept'));
      if (representation === 'none') {
        res.status(406).type('text/plain; charset=utf-8').send(NOT_ACCEPTABLE_BODY);
        return;
      }
      if (representation === 'html') return next();

      const query = new URLSearchParams(req.url.split('?')[1] ?? '');
      const markdown = await render(isMdUrl ? pagePathFromMarkdown(req.path) : req.path, query);
      if (markdown === null) {
        // No Markdown version: the .md URL is a 404, the page URL falls back to HTML.
        if (isMdUrl) {
          res.status(404).type('text/markdown; charset=utf-8').send('# Not found\n\nThere is no page at this address.\n');
          return;
        }
        return next();
      }
      res.set('Cache-Control', 'no-cache').type('text/markdown; charset=utf-8').send(markdown);
    } catch (err) {
      next(err);
    }
  };
}
