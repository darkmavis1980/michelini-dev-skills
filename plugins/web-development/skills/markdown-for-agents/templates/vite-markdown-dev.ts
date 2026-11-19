// Vite plugin: the dev-server twin of the nginx rules, so `npm run dev` answers like production.
// `pages()` returns the same Map the build emits (file name → Markdown), e.g. 'index.md',
// 'blog.md', 'blog/my-post.md'. With the HTML-to-Markdown approach (html-to-markdown.mjs) there
// is no dev source: skip this plugin and test against `vite preview` + nginx (Docker) instead.
//
// Source: michelini.dev scripts/vite-posts.ts (ADRs 0009, 0010).
import type { Plugin } from 'vite';
import { NOT_ACCEPTABLE_BODY, isPagePath, markdownPath, negotiate } from './src/lib/negotiate';

export function markdownPages(pages: () => Map<string, string>): Plugin {
  return {
    name: 'markdown-pages',
    // Emit the .md files next to the build output.
    generateBundle() {
      for (const [fileName, source] of pages()) this.emitFile({ type: 'asset', fileName, source });
    },
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const pathname = (req.url ?? '/').split('?')[0];
        const isMdUrl = pathname.endsWith('.md');
        const isPage = isPagePath(pathname) && !pathname.startsWith('/@'); // /@vite/... internals
        const representation = isMdUrl ? 'md' : isPage ? negotiate(req.headers.accept) : 'html';
        if (representation === 'none') {
          res.statusCode = 406;
          res.setHeader('Content-Type', 'text/plain; charset=utf-8');
          res.setHeader('Vary', 'Accept');
          return res.end(NOT_ACCEPTABLE_BODY);
        }
        if (representation !== 'md') return next();
        const file = (isMdUrl ? pathname : markdownPath(pathname)).replace(/^\//, '');
        let page: string | undefined;
        try {
          page = pages().get(file);
        } catch {
          return next();
        }
        if (page === undefined) return next();
        res.setHeader('Content-Type', 'text/markdown; charset=utf-8');
        res.setHeader('Vary', 'Accept');
        res.end(page);
      });
    },
  };
}
