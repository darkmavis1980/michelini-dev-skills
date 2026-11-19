---
id: hard-rules
version: 1
title: Hard rules (migrations, git)
description: Never run database migrations; never commit or push
---
## Hard rules

- **Never run migrations.** Not `migrate:up`, `migrate:down`, or any migration command. They touch
  the live database and can destroy data if run at the wrong time or against the wrong
  environment. Write the migration file and let the user run it.
- **Never commit or push.** The user does both, often mid-session. New commits or staged files of
  your changes are the user's, not a hook. Don't flag them or offer to reset.
