#!/usr/bin/env node
// PreToolUse hook for Bash. Blocks commands a project has opted out of letting Claude run.
//
// Opt-in per project: does nothing unless <project>/.claude/guards.json exists, e.g.
//   { "block": ["migrations", "git-write"] }
//
// Rules:
//   migrations  Applying or rolling back DB migrations (migrate:up/down/latest/rollback/reset,
//               prisma migrate deploy/dev/reset, drizzle-kit push/migrate, sequelize db:migrate).
//               migrate:status and migrate:create stay allowed.
//   git-write   git commit and git push (any flags, -C <dir> too).
//
// Exit 2 blocks the call and sends stderr to Claude. Any other failure exits 0 so a broken
// guard never blocks normal work. This is a guardrail against mistakes, not a security boundary.

import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

let input;
try {
  input = JSON.parse(readStdin() || '{}');
} catch {
  process.exit(0);
}

const command = input?.tool_input?.command;
if (input?.tool_name !== 'Bash' || typeof command !== 'string') process.exit(0);

const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
const configFile = path.join(projectDir, '.claude', 'guards.json');
if (!existsSync(configFile)) process.exit(0);

let block;
try {
  block = new Set(JSON.parse(readFileSync(configFile, 'utf8')).block ?? []);
} catch {
  process.stderr.write(`guard-commands: could not parse ${configFile}, guards disabled\n`);
  process.exit(0);
}

// Split into simple commands so `cd x && git push` is caught, and drop leading env assignments.
const segments = command
  .split(/&&|\|\||;|\||\n|\$\(|`/)
  .map((s) => s.trim().replace(/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+/, '').replace(/^(?:sudo|exec|time|command)\s+/, ''))
  .filter(Boolean);

const MIGRATION_PATTERNS = [
  /\bmigrate:(?:up|down|latest|rollback|reset|redo|fresh|refresh)\b/,
  /\bprisma\s+migrate\s+(?:deploy|dev|reset)\b/,
  /\bprisma\s+db\s+push\b/,
  /\bdrizzle-kit\s+(?:push|migrate)\b/,
  /\bsequelize(?:-cli)?\s+db:migrate\b/,
  /\bknex\s+migrate:(?:latest|up|down|rollback)\b/,
];

function gitSubcommand(seg) {
  const t = seg.split(/\s+/);
  if (t[0] !== 'git') return null;
  for (let i = 1; i < t.length; i++) {
    if (t[i] === '-C' || t[i] === '-c' || t[i] === '--git-dir' || t[i] === '--work-tree') i++;
    else if (!t[i].startsWith('-')) return t[i];
  }
  return null;
}

const hits = [];
for (const seg of segments) {
  if (block.has('migrations') && MIGRATION_PATTERNS.some((re) => re.test(seg))) {
    hits.push(
      `Blocked by .claude/guards.json ("migrations"): \`${seg}\`.\n` +
        'Migrations touch the live database. Write the migration file, then tell the user the exact command to run themselves.',
    );
  }
  const sub = block.has('git-write') ? gitSubcommand(seg) : null;
  if (sub === 'commit' || sub === 'push') {
    hits.push(
      `Blocked by .claude/guards.json ("git-write"): \`${seg}\`.\n` +
        'The user commits and pushes themselves. Leave the changes in the working tree and summarise them instead.',
    );
  }
}

if (hits.length) {
  process.stderr.write(hits.join('\n') + '\n');
  process.exit(2);
}
process.exit(0);
