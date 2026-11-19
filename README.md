# michelini-dev-skills

A personal [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces): one place to keep the skills, MCP servers and hooks I find useful.

## Install

```sh
# from a local checkout
/plugin marketplace add ~/Code/michelini-dev-skills

# or from GitHub
/plugin marketplace add darkmavis1980/michelini-dev-skills

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
| `dev-workflow` | Workflow tools: `mental-model` (architecture doc with Mermaid diagrams), `stepwise-plan` (plan file run one task at a time with review stops), `agent-snippets` (versioned instruction snippets for `CLAUDE.md` / `AGENTS.md`: communication style, hard rules, package versions), plus the **Plain English** output style (ELI5 + ASD-STE-100). |
| `aws` | AWS setup and checks: `ses-transactional-email` (SES for an app's transactional email: DKIM, MAIL FROM, DMARC, sandbox, send-only IAM, mailer example, check scripts), `s3-private-bucket` (private bucket setup and read-back checks, presigned uploads/downloads, least-privilege IAM). |
| `web-development` | Full-stack TypeScript npm-workspaces monorepos on a VPS: `npm-workspaces-monorepo` (scaffold or extend the house layout), `express-api-conventions` (routes/services/AppError/Kysely migrations/tests), `env-var-sync` (check `.env.sample` vs `.env.docker` vs PM2), `vps-release-pipeline` (PR checks, tag-exact release deploy, `update.sh`, PM2 + nginx samples), `markdown-for-agents` (serve pages as Markdown on `Accept: text/markdown`: nginx maps, Next.js, Express, check script), plus an opt-in hook that blocks migrations and git commit/push. |
