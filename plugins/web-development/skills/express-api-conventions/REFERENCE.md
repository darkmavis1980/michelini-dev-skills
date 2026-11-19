# Express API conventions: code shapes

Copy these shapes; rename to fit the area. They follow the existing servers in the monorepos this was drawn from.

## `src/errors.ts`

```ts
export class AppError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = 'AppError';
  }
}
```

## Global error handler (end of `src/index.ts`)

```ts
import { ZodError } from 'zod';

app.use((err: Error & { status?: number }, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof ZodError) {
    res.status(400).json({ error: 'Invalid request', details: err.issues });
    return;
  }
  const status = err.status ?? 500;
  if (status >= 500) console.error(err);
  // Don't leak internal messages on 500s.
  res.status(status).json({ error: status >= 500 ? 'Internal server error' : err.message });
});
```

Startup order in `index.ts`: load env, build the app, `await migrateToLatest()`, then `app.listen(PORT)`. Exit non-zero if startup throws so PM2 and Docker show the failure.

## Route (`src/routes/widgets.ts`)

```ts
import { Router, type Request, type Response, type NextFunction } from 'express';
import { z } from 'zod';
import { listWidgets, getWidget, createWidget } from '../services/widgetsService.js';
import { writeLimiter } from '../middleware/rateLimit.js';
import { csrfProtection } from '../middleware/csrf.js';
import { requireUser, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const createSchema = z.object({
  name: z.string().min(1).max(160),
  url: z.url().max(2000).optional(),
});

router.get('/', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    res.json({ widgets: await listWidgets() });
  } catch (err) {
    next(err);
  }
});

// Literal paths before `/:id` so they aren't swallowed as an id.
router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = z.uuid().parse(req.params.id);
    res.json({ widget: await getWidget(id) });
  } catch (err) {
    next(err);
  }
});

router.post('/', writeLimiter, csrfProtection, requireUser, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const body = createSchema.parse(req.body);
    const widget = await createWidget(body, (req as AuthedRequest).user.id);
    res.status(201).json({ widget });
  } catch (err) {
    next(err);
  }
});

export default router;
```

Mount it in `index.ts`: `app.use('/api/widgets', widgetsRouter);`. Unsafe methods (POST/PUT/PATCH/DELETE) get the rate limiter and CSRF middleware the repo already uses.

## Service (`src/services/widgetsService.ts`)

```ts
import { db } from '../database/connection.js';
import { AppError } from '../errors.js';

export async function listWidgets() {
  return db.selectFrom('widgets').select(['id', 'name', 'url', 'created_at']).orderBy('created_at', 'desc').execute();
}

export async function getWidget(id: string) {
  const row = await db.selectFrom('widgets').select(['id', 'name', 'url', 'created_at']).where('id', '=', id).executeTakeFirst();
  if (!row) throw new AppError('Widget not found', 404);
  return row;
}

export async function createWidget(input: { name: string; url?: string }, createdBy: string) {
  return db
    .insertInto('widgets')
    .values({ name: input.name, url: input.url ?? null, created_by: createdBy })
    .returning(['id', 'name', 'url', 'created_at'])
    .executeTakeFirstOrThrow();
}
```

Select explicit columns. Don't `selectAll()` on tables that hold secrets, hashes or personal data.

## Migration (`migrations/20261119120000_create_widgets.ts`)

```ts
import { Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable('widgets')
    .addColumn('id', 'uuid', (c) => c.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn('name', 'text', (c) => c.notNull())
    .addColumn('url', 'text')
    .addColumn('created_by', 'uuid', (c) => c.references('users.id').onDelete('set null'))
    .addColumn('created_at', 'timestamptz', (c) => c.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema.createIndex('widgets_created_at_idx').on('widgets').column('created_at').execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable('widgets').execute();
}
```

Changing an existing table without breaking the running server:

1. Migration A: add the new column as nullable (or with a default). Ship code that writes both old and new.
2. Backfill in the same or a later migration.
3. Migration B, in a later release: add `NOT NULL`, drop the old column.

Then add the table to `src/database/types.ts` (`Generated<…>` for defaulted columns).

## Migrator (`src/database/migrator.ts`)

Kysely `FileMigrationProvider` over `apps/server/migrations/`, plus `migrateToLatest()` for startup and a small CLI (`migrate-cli.ts up|down|status`). `package.json` scripts:

```json
{
  "dev": "tsx watch src/index.ts",
  "start": "node --import tsx/esm src/index.ts",
  "typecheck": "tsc --noEmit",
  "test": "vitest run",
  "migrate:up": "tsx src/database/migrate-cli.ts up",
  "migrate:down": "tsx src/database/migrate-cli.ts down",
  "migrate:status": "tsx src/database/migrate-cli.ts status",
  "migrate:create": "tsx src/database/create-migration.ts"
}
```

`tsx` is needed at runtime by `start`, so keep it in `dependencies` (or don't install with `--omit=dev`).

## Vitest config (`apps/server/vitest.config.ts`)

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    // Source uses NodeNext-style `.js` specifiers that point at `.ts` files.
    extensionAlias: { '.js': ['.ts', '.js'] },
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    env: {
      // Test-only values. Never real secrets.
      JWT_SECRET: 'test-secret-not-used-anywhere-else',
    },
  },
});
```

## Test (`tests/services/widgetsService.test.ts`)

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest';

const executeTakeFirst = vi.fn();
vi.mock('../../src/database/connection.js', () => ({
  db: {
    selectFrom: () => ({ select: () => ({ where: () => ({ executeTakeFirst }) }) }),
  },
}));

const { getWidget } = await import('../../src/services/widgetsService.js');

describe('getWidget', () => {
  beforeEach(() => executeTakeFirst.mockReset());

  it('throws a 404 AppError when the row is missing', async () => {
    executeTakeFirst.mockResolvedValue(undefined);
    await expect(getWidget('00000000-0000-0000-0000-000000000000')).rejects.toMatchObject({ status: 404 });
  });
});
```

Pure helpers (pricing, parsing, date maths) are the best test targets: no mocks needed.
