# Reference

## DNS records at a glance

| Record | Name | Value | Why |
| --- | --- | --- | --- |
| DKIM × 3 | `<token>._domainkey.example.com` | CNAME `<token>.dkim.amazonses.com` | Signs mail as your domain. DMARC passes on DKIM alone |
| MAIL FROM MX | `mail.example.com` | `10 feedback-smtp.<region>.amazonses.com` | Bounces come back to SES. The region must match the identity's |
| MAIL FROM SPF | `mail.example.com` | `"v=spf1 include:amazonses.com ~all"` | SPF passes and aligns with `example.com` |
| DMARC | `_dmarc.example.com` | `"v=DMARC1; p=none; rua=mailto:dmarc@example.com"` | Tells receivers what to do with unauthenticated mail, and sends you reports |

- **One SPF record per name.** Two `v=spf1` records on the same name is an error for receivers. Merge them.
- **Root SPF:** leave it for other senders (Google Workspace and so on). With a custom MAIL FROM, SES doesn't need to be in it.
- **Cloudflare:** DKIM CNAMEs and MX/TXT records must be DNS only (grey cloud). Proxied CNAMEs break DKIM.
- **`BehaviorOnMxFailure`:** if the MAIL FROM MX disappears, SES either falls back to `amazonses.com` (`USE_DEFAULT_VALUE`, so SPF stops aligning) or rejects the send. The default fallback is safer for delivery.

## Sandbox and limits

- In the sandbox, SES only sends to verified identities, and quotas are small. `check-account.sh` shows `ProductionAccessEnabled`.
- After production access, the quota grows with use. Transactional apps rarely hit it.
- SES watches the bounce and complaint rates and can pause sending. As AWS documents it, the account is reviewed at roughly 5% bounces or 0.1% complaints, and sending can pause at about 10% / 0.5%. Check the current numbers in the SES Reputation metrics page.

## Bounces and complaints

- **Account-level suppression list:** enable it for `BOUNCE` and `COMPLAINT` (`check-account.sh` shows it). SES then stops sending to addresses that bounced or complained, which protects the account's reputation without any app code.
- **For low-volume transactional mail,** that's usually enough. For more, add a configuration set with an event destination (SNS or EventBridge) for bounce and complaint events, and mark the address in the app. Keep tracking off on that configuration set.
- **Test** with `send-test.sh --to bounce@simulator.amazonses.com` and `--to complaint@simulator.amazonses.com`.

## Common errors

| Error | Cause |
| --- | --- |
| `MessageRejected: Email address is not verified` | The From domain isn't verified **in this region**, or, in the sandbox, the recipient isn't verified |
| `AccessDenied ... ses:SendEmail` | The IAM policy's resource (region, account, domain) or its `ses:FromAddress` condition doesn't match the From address. A display name is fine: the condition sees the address only |
| `AccessDenied ... configuration-set` | The send names a configuration set the policy doesn't list |
| Mail arrives in spam | DKIM not `SUCCESS` yet, DMARC `quarantine` with DKIM failing, or a new domain with no reputation. Check the received headers for `dkim=pass` / `dmarc=pass` |
| Sign-in links broken | Link tracking is on (a configuration set with click tracking). Turn it off for transactional mail |
| Requests hang | No timeout on the SDK call. Pass an `abortSignal` (as in `examples/mailer.ts`) |

## Moving from another provider

1. Set up SES (steps 1–4), and keep the old provider's DNS until the switch.
2. Switch the app's mailer and deploy. Check one real email end to end.
3. Remove the old provider's API keys from every environment, and its DKIM/SPF records once nothing sends through it.
4. Update the privacy policy: remove the old processor and any transfer wording that only applied to it.
