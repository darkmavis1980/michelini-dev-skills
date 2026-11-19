# aws

Skills for setting up and checking the AWS services small web apps use.

## Skills

| Skill | What it does |
| --- | --- |
| `ses-transactional-email` | Sets up Amazon SES for an app's transactional email (DKIM, custom MAIL FROM, SPF/DMARC, leaving the sandbox, a send-only IAM policy, a Node mailer example with tests, bounce handling, privacy-policy wording). Scripts: `check-dns.sh` (public records, read-only), `check-account.sh` (account and identity status, read-only), `send-test.sh` (one email to the SES mailbox simulator by default). |
| `s3-private-bucket` | Sets up a private S3 bucket for an app's files (ACLs off, public access blocked, versioning, SSE-S3, TLS-only policy, lifecycle, CORS for browser uploads, least-privilege IAM) and the app code for presigned multipart uploads and version-exact downloads. Scripts: `setup-bucket.sh` (idempotent, `--dry-run`, names the failed step), `check-bucket.sh` (reads every setting back, tests from outside and with the app's keys; read-only except `--roundtrip`). |

Requires `bash`, `curl` and `dig`; the AWS CLI v2 for the SES account/test scripts and both bucket scripts.

## Install

```
/plugin install aws@michelini-dev-skills
```
