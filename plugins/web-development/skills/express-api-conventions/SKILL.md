---
name: express-api-conventions
description: House conventions for an Express 5 + TypeScript (ESM) + Kysely + Postgres API in an npm-workspaces monorepo (apps/server) — thin routes with zod validation, business logic and DB access in services, AppError for HTTP status, Kysely migrations named YYYYMMDDhhmmss_snake_case.ts that the user runs, tests in tests/ mirroring src/. Use this whenever you add or change an endpoint, route, service, middleware, migration, database table or server test in such a repo, or when the user says "add an API endpoint", "new route", "new table", "write a migration", "add a service".
---

# Express API conventions

The layout this applies to:

```
apps/server/
  src/index.ts            # app, middleware order, global error handler, migrateToLatest() on start
  src/errors.ts           # AppError(message, status)
  src/routes/*.ts         # thin controllers, one Router per area
  src/services/*.ts       # business logic + every DB query
  src/middleware/*.ts     # auth, csrf, rateLimit
  src/database/           # connection.ts, types.ts, migrator.ts, migrate-cli.ts, create-migration.ts
  migrations/             # YYYYMMDDhhmmss_snake_case.ts with up/down
  tests/                  # mirrors src/: tests/services/foo.test.ts
```

Code shapes for each part are in [REFERENCE.md](REFERENCE.md). Read it before writing a new route, service, migration or test.

## Rules

**Routes are thin.** Parse and validate input with zod, call one service function, send the response. No `db` import in a route file. Every handler is `try { … } catch (err) { next(err) }`. Express 5 also forwards rejected promises, but keep the explicit form for consistency with existing routes.

**Services own logic and queries.** They throw `AppError('Not found', 404)` for business errors. The global error handler maps `ZodError` to 400 and `err.status` to the response status, so routes never pick status codes for errors.

**Zod v4 top-level formats.** `z.uuid()`, `z.email()`, `z.url()`, `z.iso.datetime()`. Not the deprecated `z.string().uuid()` etc. Chaining still works: `z.url().max(2000)`.

**ESM with `.js` specifiers.** Import `./services/foo.js` even though the file is `foo.ts`. The server runs on `tsx`; Vitest needs `resolve.extensionAlias` to map `.js` to `.ts` (see REFERENCE.md).

**Migrations: write them, never run them.**
- Scaffold with `npm run migrate:create <name>` from `apps/server`, or create the file by hand with the same timestamp format.
- Export `up` and `down`, type the db as `Kysely<unknown>` (migrations must not depend on the current `types.ts`).
- Make them **backward compatible with the running code** (add columns as nullable or with defaults, backfill, then tighten in a later migration). The deploy runs migrations before the new server starts.
- Update `src/database/types.ts` to match.
- **Never run `migrate:up`, `migrate:down` or any migration command.** They hit whatever database `.env` points at. Tell the user the command to run. (The plugin's guard hook enforces this in projects that opt in.)

**Tests** live in `apps/server/tests/`, mirroring `src/`. No tests under `src/`, no `__tests__/`. Use the runner the repo already has (Vitest or `node --test`); new repos use Vitest. Test services directly, mock at the module boundary, keep tests independent of a real database unless the repo already has a DB test setup.

**Env vars** go in three files. Use the `env-var-sync` skill whenever you add one.

**Dependencies.** Look up the current version (context7 `resolve-library-id` then `query-docs`) before adding or updating a library, and pin the exact latest patch (`^8.0.7`, not `^8.0.0`). Install from the repo root with `npm install <pkg> -w apps/server`. Prefer a maintained library over hand-rolled code for solved, edge-case-heavy problems (dates and time zones, CSV, crypto).

**Privacy in queries.** Columns that identify staff or admins (e.g. `created_by` joins to a user name) belong only in admin-facing queries. When a public route shares a query, add a `…ForAdmin` variant instead of widening the shared one.

## Before you finish

From the repo root:

```bash
npm --workspace apps/server run typecheck
npm --workspace apps/server run lint --if-present
npm --workspace apps/server test
```

All must pass. If you wrote a migration, end your reply with the exact command for the user to run, e.g. `cd apps/server && npm run migrate:up`.
