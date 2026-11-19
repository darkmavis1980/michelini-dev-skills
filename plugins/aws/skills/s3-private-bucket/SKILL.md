---
name: s3-private-bucket
description: Sets up and checks a private Amazon S3 bucket for an app's files (uploads, originals, exports, documents): public access blocked, ACLs off, versioning, encryption, a TLS-only policy, lifecycle rules, CORS for direct browser uploads and a least-privilege IAM policy, plus app code for presigned multipart uploads and version-exact presigned downloads. Includes an idempotent setup script that names the step that failed, and a check script that reads every setting back and tests from outside and with the app's keys. Use when an app needs to store private files in S3, when adding browser uploads or download links, or to check that an existing bucket is really private and correctly configured.
---

# Private S3 bucket

Goal: files are never public. The browser uploads and downloads directly through short-lived presigned URLs, so no file bytes pass through the app server. The app's keys can only do what the app needs. Every setting is checked by reading it back, never assumed.

## Workflow

- [ ] 1. Plan the key layout and lifecycle
- [ ] 2. Create and configure the bucket
- [ ] 3. Read everything back
- [ ] 4. Give the app a least-privilege IAM user
- [ ] 5. Add the storage code
- [ ] 6. Check with the app's keys

**1. Plan the key layout.** Use one prefix per lifecycle. The templates use two:
- `staging/` for temporary uploads, expired after 2 days;
- `files/` for kept files, whose replaced or deleted versions are kept 90 days so mistakes can be recovered.

Rename them to fit the app, and edit [templates/lifecycle.json](templates/lifecycle.json) and [templates/iam-policy.json](templates/iam-policy.json) to match. Keys shouldn't contain personal data such as emails or names: use ids. Pick the region where the app's other data lives.

**2. Create and configure** with an admin profile, never the app's keys:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-bucket.sh" <bucket> --region eu-west-1 --profile <admin> \
  --origin https://app.example.com --origin http://localhost:5173   # --dry-run first to review
```

The script disables ACLs, blocks all public access, turns on versioning and SSE-S3, applies the TLS-only policy and the lifecycle rules, and sets CORS for each `--origin`. Pass `--origin` only if browsers upload directly, and include the dev origin if uploads are tested locally. The script is idempotent, so re-running only re-applies the settings. If a step fails, it says which one, and nothing after it is applied.

**3. Read everything back.** Don't trust the setup script's output alone, because a run can stop halfway unnoticed:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-bucket.sh" <bucket> --region eu-west-1 --profile <admin> \
  --origin https://app.example.com --origin http://localhost:5173
```

It reads every setting back, then checks from outside: anonymous access is refused, plain HTTP is refused, a browser preflight passes from each origin and fails from a foreign one.

**4. IAM.** Create one IAM user for the app and attach the edited [templates/iam-policy.json](templates/iam-policy.json):
- object actions only, per prefix;
- **no** bucket-level actions;
- permanent version deletes only under `staging/`.

A presigned URL carries its signer's permissions, so this policy also limits what a leaked URL could ever do. If the app already has an IAM user (for SES, for example), attach this policy to it instead of creating more keys. Put the keys in the app's environment (for example `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION`), never in the repo.

**5. Storage code.** See [examples/storage.ts](examples/storage.ts) (Node, AWS SDK v3) and [REFERENCE.md](REFERENCE.md) for the flows:
- multipart browser uploads through presigned part URLs;
- server-side processing of staged uploads;
- downloads presigned for **one exact version**, with a 5-minute expiry, `Content-Disposition: attachment` and a safe filename, issued only after the app's own access checks.

Keep it behind an interface with an in-memory fake for tests. If the app has a CSP, add the bucket host to `connect-src` (see the `nginx-spa-security-headers` skill in the `security` plugin).

**6. Check with the app's keys.** Put them in a temporary AWS CLI profile (`aws configure --profile <app>`), then:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-bucket.sh" <bucket> --app-profile <app> --roundtrip staging/check/
```

The app's keys must **fail** to read bucket settings. If they succeed, they're broader keys, not the restricted user. The round trip writes, reads and permanently deletes one small test object, and is the script's only write. Remove the temporary profile afterwards.
