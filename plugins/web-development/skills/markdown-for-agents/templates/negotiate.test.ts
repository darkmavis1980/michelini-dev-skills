import { describe, expect, it } from 'vitest';
import { isPagePath, markdownPath, negotiate, pagePathFromMarkdown } from '../src/lib/negotiate.js';

describe('negotiate', () => {
  it('gives HTML to browsers, curl and requests with no Accept header', () => {
    expect(negotiate('text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8')).toBe('html');
    expect(negotiate('*/*')).toBe('html');
    expect(negotiate(undefined)).toBe('html');
    expect(negotiate('')).toBe('html');
  });

  it('gives Markdown when it is asked for by name', () => {
    expect(negotiate('text/markdown')).toBe('md');
    expect(negotiate('text/markdown, text/html;q=0.9')).toBe('md');
    expect(negotiate('text/markdown, */*')).toBe('md');
  });

  it('respects q-values, with ties going to Markdown', () => {
    expect(negotiate('text/html, text/markdown;q=0.1')).toBe('html');
    expect(negotiate('text/html;q=0.5, text/markdown;q=0.5')).toBe('md');
    expect(negotiate('text/markdown;q=0')).toBe('none');
    expect(negotiate('text/markdown;q=0, text/html')).toBe('html');
  });

  it('uses the most specific HTML match', () => {
    expect(negotiate('text/html;q=0.2, text/*, text/markdown;q=0.5')).toBe('md');
    expect(negotiate('text/*;q=0.9, text/markdown;q=0.5')).toBe('html');
  });

  it('returns none when neither type is acceptable', () => {
    expect(negotiate('application/json')).toBe('none');
    expect(negotiate('application/x-content-negotiation-probe')).toBe('none');
  });
});

describe('markdownPath / pagePathFromMarkdown', () => {
  it('maps a page to its .md twin, keeping the query', () => {
    expect(markdownPath('/')).toBe('/index.md');
    expect(markdownPath('/docs/setup')).toBe('/docs/setup.md');
    expect(markdownPath('/news/')).toBe('/news.md');
    expect(markdownPath('/directory?category=trades')).toBe('/directory.md?category=trades');
  });

  it('maps a .md URL back to its page', () => {
    expect(pagePathFromMarkdown('/index.md')).toBe('/');
    expect(pagePathFromMarkdown('/docs/setup.md')).toBe('/docs/setup');
  });
});

describe('isPagePath', () => {
  it('treats paths without an extension as pages', () => {
    expect(isPagePath('/')).toBe(true);
    expect(isPagePath('/blog/my-post')).toBe(true);
    expect(isPagePath('/feed.xml')).toBe(false);
    expect(isPagePath('/assets/index-abc123.js')).toBe(false);
  });
});
