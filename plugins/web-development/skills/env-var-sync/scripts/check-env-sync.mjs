#!/usr/bin/env node
// Checks that every env var an app declares is set in every place that injects env:
//   apps/<app>/.env.sample (or .env.example)  -> the source of truth for local dev
//   apps/<app>/.env.docker                    -> docker compose env_file (if the app has one)
//   ecosystem.config.sample.js                -> PM2, the only env source in the non-Docker prod deploy
//
// Read-only. Prints a report and exits 1 if a key is missing anywhere, 0 if all in sync.
//
// Usage:
//   node check-env-sync.mjs [repo-root] [--ignore KEY1,KEY2] [--app apps/server]
//
// Values are never printed, only key names.

import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
let root = process.cwd();
const ignore = new Set();
const onlyApps = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--ignore') (args[++i] ?? '').split(',').filter(Boolean).forEach((k) => ignore.add(k.trim()));
  else if (a === '--app') onlyApps.push(path.normalize(args[++i] ?? ''));
  else if (a === '-h' || a === '--help') {
    console.log('Usage: check-env-sync.mjs [repo-root] [--ignore KEY1,KEY2] [--app apps/server]');
    process.exit(0);
  } else root = path.resolve(a);
}

function dotenvKeys(file) {
  const keys = new Set();
  for (const raw of readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    // Commented-out keys ("# FOO=bar") count as documented-but-optional, so they are skipped above.
    const m = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/);
    if (m) keys.add(m[1]);
  }
  return keys;
}

function stripJsComments(src) {
  // Good enough for config files: drop /* */ blocks and // line comments not inside quotes.
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .map((l) => {
      let q = null;
      for (let i = 0; i < l.length; i++) {
        const c = l[i];
        if (q) {
          if (c === '\\') i++;
          else if (c === q) q = null;
        } else if (c === '"' || c === "'" || c === '`') q = c;
        else if (c === '/' && l[i + 1] === '/') return l.slice(0, i);
      }
      return l;
    })
    .join('\n');
}

function keysIn(text) {
  const keys = new Set();
  // UPPER_CASE object keys, bare or quoted: FOO: 'x', 'FOO': 1, "FOO_BAR": true
  for (const m of text.matchAll(/(?:^|[\s{,])['"]?([A-Z][A-Z0-9_]*)['"]?\s*:/gm)) keys.add(m[1]);
  return keys;
}

// Returns { all: Set, byCwd: Map<normalizedCwd, Set> }. Each app block is taken as the
// text from its `cwd:` to the next `cwd:` — true for the usual { name, cwd, script, env } order.
function ecosystemKeys(file) {
  const src = stripJsComments(readFileSync(file, 'utf8'));
  const all = keysIn(src);
  const byCwd = new Map();
  const cwds = [...src.matchAll(/\bcwd\s*:\s*['"`]([^'"`]+)['"`]/g)];
  cwds.forEach((m, i) => {
    const end = i + 1 < cwds.length ? cwds[i + 1].index : src.length;
    byCwd.set(path.normalize(m[1]).replace(/^\.\//, ''), keysIn(src.slice(m.index, end)));
  });
  return { all, byCwd };
}

function findApps() {
  const appsDir = path.join(root, 'apps');
  const dirs = existsSync(appsDir)
    ? readdirSync(appsDir)
        .map((d) => path.join('apps', d))
        .filter((d) => statSync(path.join(root, d)).isDirectory())
    : [];
  const withSample = (dir) => {
    const sample = ['.env.sample', '.env.example'].map((f) => path.join(dir, f)).find((f) => existsSync(path.join(root, f)));
    return sample ? { dir: path.normalize(dir), sample } : null;
  };
  const apps = dirs.map(withSample).filter(Boolean);
  // A root .env.sample is the app's env only in a single-app repo. In a monorepo it usually holds
  // tooling/CI keys (Cloudflare tokens, etc.), so it is checked only when asked for with --app .
  if (!apps.length || onlyApps.includes('.')) {
    const rootApp = withSample('.');
    if (rootApp) apps.push(rootApp);
  }
  return apps.filter((a) => !onlyApps.length || onlyApps.includes(a.dir));
}

const ecoFile = ['ecosystem.config.sample.js', 'ecosystem.config.sample.cjs', 'ecosystem.config.example.js']
  .map((f) => path.join(root, f))
  .find(existsSync);
const eco = ecoFile ? ecosystemKeys(ecoFile) : null;
const apps = findApps();

if (!apps.length) {
  console.error(`No .env.sample or .env.example found under ${root} (looked in apps/* and the root).`);
  process.exit(2);
}

let problems = 0;
const rel = (f) => path.relative(root, f) || '.';

for (const app of apps) {
  const sampleKeys = dotenvKeys(path.join(root, app.sample));
  const dockerFile = path.join(root, app.dir, '.env.docker');
  const targets = [];
  if (existsSync(dockerFile)) targets.push({ name: rel(dockerFile), keys: dotenvKeys(dockerFile), fallback: null });
  if (eco) {
    const block = eco.byCwd.get(app.dir);
    targets.push({
      name: `${rel(ecoFile)}${block ? ` (cwd: ${app.dir})` : ''}`,
      keys: block ?? eco.all,
      fallback: block ? eco.all : null,
    });
  }

  console.log(`\n${app.dir}  (source: ${app.sample}, ${sampleKeys.size} keys)`);
  if (!targets.length) {
    console.log('  no .env.docker or ecosystem sample found, nothing to compare');
    continue;
  }

  for (const t of targets) {
    const missing = [...sampleKeys].filter((k) => !ignore.has(k) && !t.keys.has(k));
    const extra = [...t.keys].filter((k) => !ignore.has(k) && !sampleKeys.has(k));
    if (!missing.length) console.log(`  ok    ${t.name}`);
    for (const k of missing) {
      const elsewhere = t.fallback?.has(k) ? '  (set in a different PM2 app block)' : '';
      console.log(`  MISS  ${t.name}: ${k}${elsewhere}`);
      problems++;
    }
    // Keys only in the target are often intentional (NODE_ENV, PORT in PM2), so they are informational.
    if (extra.length) console.log(`  info  ${t.name} also sets: ${extra.join(', ')}`);
  }
}

if (!eco) console.log(`\nNo ecosystem.config.sample.js at ${rel(root)}: PM2 env not checked.`);
console.log(problems ? `\n${problems} missing key(s).` : '\nAll env files in sync.');
process.exit(problems ? 1 : 0);
