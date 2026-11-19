# aws

Skills for setting up and checking the AWS services small web apps use.

## Skills

| Skill | What it does |
| --- | --- |
| `ses-transactional-email` | Sets up Amazon SES for an app's transactional email (DKIM, custom MAIL FROM, SPF/DMARC, leaving the sandbox, a send-only IAM policy, a Node mailer example with tests, bounce handling, privacy-policy wording). Scripts: `check-dns.sh` (public records, read-only), `check-account.sh` (account and identity status, read-only), `send-test.sh` (one email to the SES mailbox simulator by default). |

Requires `bash` and `dig`; the AWS CLI v2 for `check-account.sh` and `send-test.sh`.

## Install

```
/plugin install aws@michelini-dev-skills
```
