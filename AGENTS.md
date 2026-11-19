# AGENTS.md

This repo is a personal **Claude Code plugin marketplace**. It is a catalog of plugins (skills, slash commands, subagents, hooks, MCP servers). There is no application code, build step or test suite. The deliverables are the manifests and Markdown files themselves.

## Layout

- `.claude-plugin/marketplace.json`: the catalog. Every plugin under `plugins/` must have an entry here, or it can't be installed.
- `plugins/<name>/`: one folder per plugin.
  - `.claude-plugin/plugin.json`: manifest (`name`, `description`, `version`, `author`).
  - `skills/<skill-name>/SKILL.md`: skills (YAML frontmatter with `name` + `description`).
  - `commands/*.md`, `agents/*.md`: slash commands and subagents.
  - `hooks/hooks.json` + `scripts/`: hooks.
  - `.mcp.json`: MCP servers.
- `templates/plugin-template/`: starting point for new plugins. It is **not** listed in the marketplace.

## Adding or changing a plugin

1. Copy the template: `cp -R templates/plugin-template plugins/<name>`. Delete the parts the plugin doesn't use.
2. Keep the plugin's `name` the same in three places: the folder name, `plugin.json`, and its `marketplace.json` entry.
3. Add or update the entry in `.claude-plugin/marketplace.json` (`name`, `source: "./plugins/<name>"`, `description`, `version`).
4. Bump `version` (semver) in both `plugin.json` and the marketplace entry when a plugin changes, so `/plugin marketplace update` picks it up.
5. Update the plugin table in `README.md`.
6. Validate before finishing:
   ```sh
   claude plugin validate .
   claude plugin validate plugins/<name>
   ```
   Fix errors and warnings. You can ignore the "plugin directory" submission checks (LICENSE, icon, README length) unless the user asks to publish to the official directory.

## Conventions

- **Grouping:** group related items into one plugin by topic (e.g. `cloudflare`, `frontend`, `git-workflow`) rather than one plugin per skill, unless an item is large or standalone.
- **Names:** use kebab-case for plugin, skill, command and agent names.
- **Skill descriptions:** say what the skill does *and* when to use it, including trigger phrases. Claude decides whether to load a skill from this field alone. Keep `SKILL.md` focused and move long reference material into sibling files that it links to.
- **Hooks:** reference scripts through `"${CLAUDE_PLUGIN_ROOT}/scripts/..."` (quoted), make them executable (`chmod +x`), and read hook input as JSON from stdin. Exit `2` blocks the action and sends stderr to Claude.
- **MCP servers:** pin package versions (`pkg@1.2.3`, never `latest`). Never commit secrets. Reference them as `${ENV_VAR}` and say in the plugin README which variables the user must set.
- **Third-party items:** when adding a skill, hook or MCP server found elsewhere, note its source URL and license in the plugin's README. Read any scripts before adding them.
- **Privacy:** don't add email addresses or other personal details to manifests unless the user asks.
