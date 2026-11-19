#!/usr/bin/env node
// Inserts and updates reusable instruction snippets in CLAUDE.md / AGENTS.md.
//
// Each snippet lives in ../snippets/<id>.md with frontmatter (id, version, title, description).
// In the target file it is wrapped in markers so it can be found and updated later:
//   <!-- snippet:<id> v<version> -->
//   ...body...
//   <!-- /snippet:<id> -->
//
// Usage:
//   snippet.mjs list
//   snippet.mjs check <file>                 # which snippets are present, outdated, edited, missing
//   snippet.mjs apply <id> <file> [--dry-run] # insert (append) or replace in place
//   snippet.mjs remove <id> <file> [--dry-run]
//
// Text outside the markers is never touched.

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SNIPPETS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'snippets');

function parseSnippet(file) {
  const raw = readFileSync(file, 'utf8');
  const m = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) throw new Error(`${file}: missing frontmatter`);
  const meta = Object.fromEntries(
    m[1]
      .split('\n')
      .map((l) => l.match(/^([a-z-]+):\s*(.*)$/))
      .filter(Boolean)
      .map(([, k, v]) => [k, v.replace(/^['"]|['"]$/g, '')]),
  );
  return { ...meta, version: Number(meta.version ?? 1), body: m[2].trim() };
}

function loadSnippets() {
  return readdirSync(SNIPPETS_DIR)
    .filter((f) => f.endsWith('.md'))
    .map((f) => parseSnippet(path.join(SNIPPETS_DIR, f)))
    .sort((a, b) => a.id.localeCompare(b.id));
}

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const blockRe = (id) => new RegExp(`<!-- snippet:${esc(id)} v(\\d+) -->\\n([\\s\\S]*?)\\n?<!-- /snippet:${esc(id)} -->`);
const render = (s) => `<!-- snippet:${s.id} v${s.version} -->\n${s.body}\n<!-- /snippet:${s.id} -->`;

// [start, end) of an unmarked section whose heading matches the snippet's first line.
function adoptRange(text, s) {
  const h = s.body.split('\n')[0].match(/^(#{1,6})\s+(.+?)\s*$/);
  if (!h) return null;
  const level = h[1].length;
  const lines = text.split('\n');
  let offset = 0;
  let start = -1;
  let inFence = false;
  for (const line of lines) {
    if (/^\s*(```|~~~)/.test(line)) inFence = !inFence;
    // `# comment` lines inside fenced code are not headings.
    const m = inFence ? null : line.match(/^(#{1,6})\s+(.+?)\s*$/);
    if (start < 0 && m && m[1].length === level && m[2].toLowerCase() === h[2].toLowerCase()) start = offset;
    else if (start >= 0 && m && m[1].length <= level) return [start, offset];
    offset += line.length + 1;
  }
  return start >= 0 ? [start, text.length] : null;
}

function die(msg, code = 1) {
  console.error(msg);
  process.exit(code);
}

const [cmd, ...rest] = process.argv.slice(2);
const dryRun = rest.includes('--dry-run');
const args = rest.filter((a) => a !== '--dry-run');
const snippets = loadSnippets();
const byId = new Map(snippets.map((s) => [s.id, s]));

if (!cmd || cmd === 'list') {
  for (const s of snippets) console.log(`${s.id.padEnd(22)} v${s.version}  ${s.title}: ${s.description}`);
  process.exit(0);
}

if (cmd === 'check') {
  const [file] = args;
  if (!file || !existsSync(file)) die(`check: file not found: ${file ?? '(none)'}`, 2);
  const text = readFileSync(file, 'utf8');
  let stale = 0;
  for (const s of snippets) {
    const m = text.match(blockRe(s.id));
    if (!m) {
      console.log(`missing   ${s.id}`);
      continue;
    }
    const have = Number(m[1]);
    const edited = m[2].trim() !== s.body && have === s.version;
    if (have < s.version) {
      console.log(`outdated  ${s.id} (file v${have}, latest v${s.version})`);
      stale++;
    } else if (edited) console.log(`edited    ${s.id} (v${have}, text differs from the snippet: local edit)`);
    else console.log(`ok        ${s.id} v${have}`);
  }
  // Markers for snippets this version doesn't know about.
  for (const m of text.matchAll(/<!-- snippet:([a-z0-9-]+) v\d+ -->/g)) {
    if (!byId.has(m[1])) console.log(`unknown   ${m[1]} (no such snippet in the library)`);
  }
  process.exit(stale ? 1 : 0);
}

if (cmd === 'apply' || cmd === 'remove') {
  const [id, file] = args;
  const s = byId.get(id);
  if (!s) die(`${cmd}: unknown snippet "${id}". Run "snippet.mjs list".`, 2);
  if (!file) die(`${cmd}: missing target file`, 2);
  const text = existsSync(file) ? readFileSync(file, 'utf8') : '';
  const re = blockRe(id);
  let next;
  let action;
  if (cmd === 'apply') {
    if (re.test(text)) {
      next = text.replace(re, render(s));
      action = next === text ? 'unchanged' : 'updated';
    } else if (adoptRange(text, s)) {
      // The file already has this section by hand (same heading, no markers): replace it
      // up to the next heading of the same or higher level, so it isn't duplicated.
      const [start, end] = adoptRange(text, s);
      next = text.slice(0, start) + render(s) + '\n' + (end < text.length ? '\n' + text.slice(end).replace(/^\n+/, '') : '');
      action = 'adopted (replaced the existing unmarked section)';
    } else {
      next = (text.trimEnd() ? text.trimEnd() + '\n\n' : '') + render(s) + '\n';
      action = 'appended';
    }
  } else {
    if (!re.test(text)) die(`remove: ${id} not found in ${file}`, 1);
    next = text.replace(new RegExp(`\\n*${re.source}\\n?`), '\n');
    action = 'removed';
  }
  if (dryRun) {
    console.log(`[dry-run] would be ${action}: ${id} in ${file}`);
    if (action !== 'unchanged') console.log('\n' + (cmd === 'apply' ? render(s) : '(block removed)'));
  } else {
    if (action !== 'unchanged') writeFileSync(file, next);
    console.log(`${action}: ${id} v${s.version} in ${file}`);
  }
  process.exit(0);
}

die(`unknown command "${cmd}". Use list | check | apply | remove.`, 2);
