# dev-workflow

Development workflow skills, reusable agent-instruction snippets, and an output style.

## Skills

| Skill | What it does |
| --- | --- |
| `mental-model` | Builds or refreshes `docs/mental-model.md`: what the product does, how the pieces fit, data flow, vocabulary, invariants, with Mermaid diagrams. |
| `stepwise-plan` | Writes a step-by-step implementation plan file, then runs it one task at a time with a review stop after each task. |
| `agent-snippets` | Inserts, updates, checks and removes versioned instruction snippets in `CLAUDE.md` / `AGENTS.md` (`communication-style`, `hard-rules`, `package-versions`). Script: `snippet.mjs` (`list`, `check`, `apply`, `remove`, `--dry-run`). It takes over a hand-written section with the same heading instead of duplicating it. |

## Output style

**Plain English**: the ELI5 + ASD-STE-100 communication style, with Claude Code's coding instructions kept (`keep-coding-instructions: true`). It is never forced on. Pick it per project with `/output-style` or `/config` → Output style, which saves to `.claude/settings.local.json`. To share it with the repo, set `"outputStyle": "dev-workflow:Plain English"` in `.claude/settings.json` (the value is case-sensitive). Only one output style is active at a time, and it applies to Claude Code only. For other agents, use the `communication-style` snippet in `AGENTS.md` instead.

## Requirements

Node.js 24+ for `snippet.mjs`.

## Install

```
/plugin install dev-workflow@michelini-dev-skills
```
