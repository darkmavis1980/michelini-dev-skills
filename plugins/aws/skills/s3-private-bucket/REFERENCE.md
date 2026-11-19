# Reference

## Flows

**Browser upload (multipart):**
1. The app checks the user may upload, then calls `CreateMultipartUpload` on a `staging/<id>/<random>` key.
2. For each part, the app presigns `UploadPart` (15 minutes is plenty), and the browser `PUT`s the part's bytes to that URL.
3. The browser reads each response's `ETag`, which needs CORS `ExposeHeaders: ETag`, and sends the list back to the app.
4. The app calls `CompleteMultipartUpload`, then processes the staged object (validates, stamps metadata, hashes) and writes the kept copy under `files/`. Versioning gives each write a version id: store it.
5. On cancel or error, call `AbortMultipartUpload`. The lifecycle rule cleans up anything abandoned anyway.

**Download:**
1. The app checks access, then presigns `GetObject` for the stored **version id**, so a later replacement never changes what an earlier link serves.
2. It sets `ResponseContentDisposition: attachment; filename="..."` (see `contentDisposition()` in the example, which uses an ASCII fallback plus RFC 6266 `filename*`), and a short expiry such as 300 s.
3. It returns the URL with `Cache-Control: no-store`, and the browser navigates to it. Navigations need no CORS. Log the download with the version id if downloads are evidence of anything.

Never proxy the file's bytes through the app and never make objects public. A CDN in front of a private bucket is a separate design (CloudFront with origin access control and signed URLs). Don't improvise it with a public bucket.

## Settings and why

| Setting | Why |
| --- | --- |
| Object ownership `BucketOwnerEnforced` | Disables ACLs, so no object can be made public by an ACL |
| Block all public access (4 × true) | Refuses public ACLs and public bucket policies, even by mistake |
| Versioning | Replacements and deletes become recoverable versions, and downloads can pin a version |
| SSE-S3 default encryption | Encryption at rest without per-request headers (some S3-compatible stores reject those) |
| Policy: deny `aws:SecureTransport = false` | No plain-HTTP access, even with valid credentials |
| Lifecycle | Aborts incomplete multipart uploads (their parts are billed but invisible), expires staging, keeps old versions for a fixed time only, removes expired delete markers |
| CORS (PUT, ETag exposed) | Only for direct browser uploads, only from the app's origins |

## SDK details that matter

- **Browser PUTs and checksums.** AWS SDK v3 adds checksum headers by default, and a browser `PUT`ing to a presigned part URL can't send them, so the upload fails with signature or checksum errors. Create the client with `requestChecksumCalculation: 'WHEN_REQUIRED'` and `responseChecksumValidation: 'WHEN_REQUIRED'`.
- **Large server-side uploads:** `@aws-sdk/lib-storage` `Upload` handles multipart (for example 16 MB parts, 4 at a time).
- **Region and endpoint:** the presigned host is `https://<bucket>.s3.<region>.amazonaws.com` (virtual-hosted style). S3-compatible stores (R2, MinIO) need `endpoint` and often `forcePathStyle: true`, and their bucket settings are configured with their own tools, not these scripts.

## Least privilege, explained

- **Object-level actions per prefix.** No `s3:ListBucket` unless the app lists keys (then add it on the bucket ARN with an `s3:prefix` condition). No bucket configuration actions at all.
- **`s3:DeleteObject` without a version id adds a delete marker,** which can be recovered until lifecycle removes it. `s3:DeleteObjectVersion` deletes for good, so allow it only where that's intended (staging cleanup).
- **A leaked presigned URL** can do exactly one operation on one key until it expires, and never more than its signer's policy allows.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Browser upload fails, preflight `403` | No CORS rule for that origin (often the dev origin), or the bucket has no CORS at all: re-run `setup-bucket.sh` with every `--origin` |
| Upload parts succeed but completion fails | `ETag` not exposed by CORS, so the browser read an empty ETag |
| `SignatureDoesNotMatch` / checksum errors on browser PUT | SDK checksums. See "Browser PUTs and checksums" |
| `NoSuchBucketPolicy` / `NoSuchLifecycleConfiguration` / `NoSuchCORSConfiguration` | Setup stopped before that step. Re-run it (it's idempotent) and read the step it names |
| `AccessDenied` on `GetObject` with a version id | The policy lacks `s3:GetObjectVersion` |
| Versions in a presigned download don't match | The app presigned without `VersionId`, so it serves whatever is current |
| The app's keys can read bucket settings | They're not the restricted user: check which IAM user the deployed keys belong to (`aws sts get-caller-identity`) |
| Test objects linger | No lifecycle rule for that prefix, or versioning keeps the old versions: delete by version id, or let lifecycle expire them |
