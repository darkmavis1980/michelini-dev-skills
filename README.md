# michelini-dev-skills

A personal [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces): one place to keep the skills, MCP servers and hooks I find useful.

## Install

```sh
# from a local checkout
/plugin marketplace add ~/Code/michelini-dev-skills

# or from the git remote (needs SSH access to the server)
/plugin marketplace add git@192.168.68.197:darkmavis1980/michelini-dev-skills.git

# then install a plugin
/plugin install security@michelini-dev-skills
```

Run `/plugin marketplace update michelini-dev-skills` to pick up changes.

## Layout

```
.claude-plugin/marketplace.json   # catalog: lists every plugin
plugins/<name>/                   # one folder per plugin
  .claude-plugin/plugin.json      # plugin manifest
  skills/<skill>/SKILL.md         # skills
  commands/*.md                   # slash commands
  agents/*.md                     # subagents
  hooks/hooks.json                # hooks (scripts in scripts/, use ${CLAUDE_PLUGIN_ROOT})
  .mcp.json                       # MCP servers
templates/plugin-template/        # copy this to start a new plugin
```

## Adding a plugin

1. `cp -R templates/plugin-template plugins/<name>`
2. Set `name`/`description` in `plugins/<name>/.claude-plugin/plugin.json`, delete the parts you don't need.
3. Add an entry to `plugins` in `.claude-plugin/marketplace.json`:
   ```json
   { "name": "<name>", "source": "./plugins/<name>", "description": "...", "version": "0.1.0" }
   ```
4. Validate: `claude plugin validate .` (and `claude plugin validate plugins/<name>`).

Group related things into one plugin (e.g. `frontend`, `cloudflare`, `git-workflow`) so you can enable/disable them as a unit.

## Plugins

| Plugin | What it does |
| --- | --- |
| `security` | Security hardening and review: `nginx-spa-security-headers` (CSP + security headers for nginx-served SPAs), `deployment-audit` (read-only outside-in audit of a live site plus its deployment files, with a dated report). |
| `aws` | AWS setup and checks: `ses-transactional-email` (SES for an app's transactional email: DKIM, MAIL FROM, DMARC, sandbox, send-only IAM, mailer example, check scripts). |
