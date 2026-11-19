/**
 * Writes a Markdown copy of every prerendered page next to the build: index.md, help.md,
 * docs/setup.md and so on. nginx serves them at those URLs, and in place of the HTML when a
 * request's Accept header prefers text/markdown.
 *
 * The source is the prerendered HTML, so the Markdown can't drift from the site. Run it after
 * the SSG build: "build": "react-router build && node scripts/html-to-markdown.mjs".
 * Needs: npm install -D turndown turndown-plugin-gfm -w apps/<client>
 *
 * Source: esb-data-analyzer apps/client/scripts/markdown-pages.mjs (homebattery.ie), made
 * recursive so nested routes (docs/setup/index.html) are included.
 */
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import TurndownService from 'turndown';
import { gfm } from 'turndown-plugin-gfm';

// ---- Configure ---------------------------------------------------------------------------
const SITE = 'https://<domain>';
const BUILD_DIR = join(dirname(fileURLToPath(import.meta.url)), '../build/client'); // Vite SPA: ../dist
const TITLE_SUFFIX = / [—|-] <Site name>$/; // stripped from <title>
const SKIP = new Set([]); // route folders to leave out, e.g. 'admin'
// --------------------------------------------------------------------------------------------

const decode = (s) =>
  s
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

const insideTableHeader = (node) => {
  for (let n = node.parentNode; n; n = n.parentNode) if (n.nodeName === 'TH') return true;
  return false;
};

const turndown = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced', bulletListMarker: '-' });
turndown.use(gfm);
turndown.remove(['script', 'style', 'svg', 'form', 'input', 'select', 'textarea', 'noscript']);
// Sortable table headers keep their label in a button; every other button is a page control.
turndown.remove((node) => node.nodeName === 'BUTTON' && !insideTableHeader(node));
turndown.remove((node) => node.getAttribute?.('aria-hidden') === 'true');
// The gfm plugin keeps line breaks inside a cell, and they would end the table row.
turndown.addRule('tableCell', {
  filter: ['th', 'td'],
  replacement(content, node) {
    const first = node.parentNode.firstElementChild === node;
    return `${first ? '| ' : ' '}${content.replace(/\s*\n\s*/g, ' ').replace(/\|/g, '\\|').trim()} |`;
  },
});

function pageToMarkdown(html, path) {
  const main = html.match(/<main\b[^>]*>([\s\S]*)<\/main>/)?.[1];
  if (!main) throw new Error(`No <main> in the prerendered page for ${path}`);
  const title = decode(html.match(/<title>([^<]*)<\/title>/)?.[1] ?? '').replace(TITLE_SUFFIX, '');
  const description = decode(html.match(/<meta name="description" content="([^"]*)"/)?.[1] ?? '');

  const body = turndown
    // Site-relative links and images become absolute, so they resolve outside the site.
    .turndown(main.replace(/((?:href|src)=")\/(?!\/)/g, `$1${SITE}/`).replace(/<br\s*\/?>/g, ' '))
    .replace(/^# .*\n+/, '') // the page's own h1 is the title below
    .trim();

  return `# ${title}\n\n${description ? `> ${description}\n\n` : ''}- Web page: ${SITE}${path}\n\n---\n\n${body}\n`;
}

// Every <route>/index.html under the build, at any depth, plus the root index.html.
function findPages(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name === 'assets') continue;
    const sub = join(dir, entry.name);
    if (existsSync(join(sub, 'index.html'))) out.push(relative(BUILD_DIR, sub));
    out.push(...findPages(sub));
  }
  return out;
}

const routes = ['', ...findPages(BUILD_DIR)].filter((r) => !SKIP.has(r));
for (const route of routes) {
  const html = readFileSync(join(BUILD_DIR, route, 'index.html'), 'utf8');
  const urlPath = `/${route.split('\\').join('/')}`;
  writeFileSync(join(BUILD_DIR, `${route || 'index'}.md`), pageToMarkdown(html, urlPath));
}
console.log(`Wrote ${routes.length} Markdown pages to ${relative(process.cwd(), BUILD_DIR) || '.'}`);
