---
name: ses-transactional-email
description: Sets up and checks Amazon SES for an app's transactional email (sign-in links, receipts, notifications), covering domain verification with DKIM, a custom MAIL FROM, SPF and DMARC, leaving the sandbox, a least-privilege IAM policy, an app mailer with a dev console fallback and no link tracking, bounce and complaint handling, and the privacy-policy wording. Includes read-only scripts for DNS and the SES account, and a mailbox-simulator test send. Use when adding email sending to an app, moving from SendGrid/Mailgun/Postmark to SES, or when SES emails don't arrive or land in spam.
---

# SES transactional email

Goal: the app's emails arrive in inboxes, authenticated as the app's own domain, sent by an IAM identity that can do nothing else. Region: use the one where the app's other AWS resources and data live (for EU data, an EU region).

## Workflow

- [ ] 1. Verify the domain
- [ ] 2. Add a custom MAIL FROM, and check SPF and DMARC
- [ ] 3. Leave the sandbox
- [ ] 4. Give the app a send-only IAM policy
- [ ] 5. Add the mailer to the app
- [ ] 6. Check everything
- [ ] 7. Update the privacy policy

**1. Verify the domain** (not a single address) in the SES console for the chosen region: Identities → Create identity → Domain, with Easy DKIM (RSA 2048). Add the three `CNAME` records it shows. Behind Cloudflare, set them to **DNS only**, not proxied.

**2. Custom MAIL FROM, SPF and DMARC.** In the identity, set a MAIL FROM subdomain (for example `mail.example.com`) and add its records:
- `MX 10 feedback-smtp.<region>.amazonses.com`
- `TXT "v=spf1 include:amazonses.com ~all"`

With this, SPF aligns with the domain, so the root SPF doesn't need SES in it. Add DMARC if there's none: start with `p=none; rua=mailto:<you>`, and move to `quarantine` once DKIM passes. If DMARC is already `quarantine` or `reject`, DKIM must pass before the first send, or mail goes to spam or is rejected.

**3. Leave the sandbox.** In the sandbox, SES only sends to verified addresses, with a low quota. Request production access from the Account dashboard, describing the transactional, low-volume use. It usually takes about a day, so start early. Until then, test with your own verified address or the mailbox simulator.

**4. IAM.** Attach [templates/iam-policy.json](templates/iam-policy.json) to the app's IAM user or role, replacing the region, account, domain and From address. It allows `ses:SendEmail` from that one address only. If the app already has an IAM user (for example for S3), add the policy to that user rather than creating a second set of keys. If the app uses a configuration set, the policy also needs its ARN as a resource.

**5. The app's mailer.** See [examples/mailer.ts](examples/mailer.ts) and its [test](examples/mailer.test.ts), written for Node with `@aws-sdk/client-sesv2`:
- **An interface:** `Mailer.send({to, subject, text, html})` with two implementations, SES and console. Tests use a fake.
- **A setting:** `EMAIL_TRANSPORT=ses|console`. Default to `console` in dev, and **refuse to start in production without `ses`**.
- **The message:** SES v2 `SendEmail` with a text part and an HTML part, UTF-8, and a display name in the From address (MIME-encoded if it isn't ASCII). Give up after 10 seconds, and throw an error that names the SES error (`MessageRejected`, `AccessDenied`).
- **No click or open tracking.** Tracking rewrites links through a redirect domain, which leaks one-time tokens and drops `#fragments`. SES only tracks through a configuration set with tracking enabled, so don't attach one for sign-in mail.
- **Errors:** a failed send must not undo the business action (an order, a sale). Record it and tell the user or admin.

**6. Check** with the scripts in `${CLAUDE_SKILL_DIR}/scripts/`:
- `check-account.sh <domain> --profile <admin-profile> --region <r>`: shows production access, quota, the suppression list, and DKIM and MAIL FROM status, and prints the DKIM tokens. It needs `ses:GetAccount` and `ses:GetEmailIdentity`.
- `check-dns.sh <domain> --mail-from <sub> --region <r> --dkim <t1,t2,t3>`: checks every public record, read-only.
- `send-test.sh --from <address> --profile <p>`: sends to the SES mailbox simulator, which isn't delivered and doesn't affect reputation. `--to bounce@simulator.amazonses.com` tests the bounce path.

Then do one real end-to-end test from the app, for example a sign-in link to your own mailbox, and check its headers show `dkim=pass` and `spf=pass` for the domain.

**7. Privacy policy.** Name Amazon Web Services (Amazon SES) as a processor that sends the emails, in the region used. An EU region means no transfer outside the EU to describe for email. Remove any previous email provider.

Troubleshooting, bounce and complaint limits, and DNS details: [REFERENCE.md](REFERENCE.md).
