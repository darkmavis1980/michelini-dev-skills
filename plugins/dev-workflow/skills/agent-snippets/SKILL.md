---
name: agent-snippets
description: Add, update, check or remove reusable instruction snippets in a project's CLAUDE.md or AGENTS.md — the shared communication style (ELI5 + ASD-STE-100 Simplified Technical English), hard rules (never run migrations, never commit or push), and package-version rules (context7, pin the exact patch). Snippets are wrapped in versioned markers so they can be updated in place later. Use this whenever the user wants to "add my communication style", "add the hard rules", "add the snippet to CLAUDE.md / AGENTS.md", "update the snippets", "are my CLAUDE.md snippets up to date", sets up a new repo's agent instructions, or runs /agent-snippets.
---

# Agent snippets

Reusable blocks of agent instructions, kept in one library and copied into each repo's `CLAUDE.md` or `AGENTS.md`. They are copied, not imported, so the text is visible in the repo and works for any agent that reads `AGENTS.md`.

In the target file, each snippet sits between markers:

```markdown
<!-- snippet:communication-style v1 -->
## Communication Style
...
<!-- /snippet:communication-style -->
```

The script only changes text between markers. Everything else in the file stays as it is.

## Commands

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/agent-snippets/scripts/snippet.mjs"
node "$S" list                              # the library: id, version, what it says
node "$S" check CLAUDE.md                   # ok / outdated / edited / missing / unknown per snippet; exit 1 if outdated
node "$S" apply <id> CLAUDE.md --dry-run    # show what would change
node "$S" apply <id> CLAUDE.md              # insert, update, or take over a hand-written section
node "$S" remove <id> CLAUDE.md
```

`apply` does one of four things:
- **updated**: markers found, so the body is replaced with the latest version.
- **adopted**: no markers, but a section with the same heading exists (for example `## Communication Style` written by hand). That section is replaced by the marked block, up to the next heading of the same level.
- **appended**: neither exists, so the block goes at the end of the file.
- **unchanged**: already the latest version.

## Workflow

1. Find the target. In this repo style `CLAUDE.md` often holds only `@AGENTS.md`. If so, the snippet goes in `AGENTS.md`, never next to the `@` import. If both files have real content, ask which one.
2. Run `check` and `list`, then say which snippets are missing or outdated.
3. **Look for the same rule under another heading** before you apply. For example, "never run migrations" may be in a `## Migrations` section and "never commit" in `## Git rules`. `apply` can't see these, and would add a duplicate. Show the user the overlap and offer to remove the old text after the snippet is in.
4. For an **adopt** or an **update**, run `--dry-run` first and show the user what changes, because the existing wording may have project-specific detail worth keeping. If it does, keep that detail outside the markers, next to the block.
5. Apply. Then run `check` again: everything you applied must be `ok`.
6. Placement: an appended block lands at the end. If it belongs near the top (the communication style and hard rules usually do), move the whole block, markers included, with an edit.

`edited` from `check` means someone changed the text inside the markers by hand. Don't overwrite it without asking. Either put the change into the library snippet (and bump its version), or move the change outside the markers.

## Adding a snippet to the library

Create `snippets/<id>.md` in this skill's folder:

```markdown
---
id: <kebab-case-id, same as the file name>
version: 1
title: <short title>
description: <one line: what the rule says>
---
## <Heading the block starts with>

<the instruction text>
```

When you change a snippet's text, bump `version`, then bump the plugin version so `/plugin marketplace update` picks it up. Repos then show `outdated` in `check` until `apply` updates them.

## Related: the output style

The communication style also ships as the **Plain English** output style in this plugin (`output-styles/plain-english.md`). It applies to Claude Code only and replaces any other output style. The snippet works in `AGENTS.md` for every agent. Use one or the other in a repo, not both, or the instruction is given twice.
