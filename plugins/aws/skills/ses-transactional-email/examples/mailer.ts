// Example mailer: Amazon SES (v2 API) behind a small interface, with a console fallback for dev.
// Wire it up with e.g. EMAIL_TRANSPORT=ses|console; require `ses` in production.
import { SESv2Client, SendEmailCommand } from '@aws-sdk/client-sesv2';

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export interface Mailer {
  send(message: EmailMessage): Promise<void>;
}

/** The one SES call the mailer makes; tests pass a fake. */
export interface SesSender {
  send(command: SendEmailCommand, options?: { abortSignal?: AbortSignal }): Promise<unknown>;
}

export const SEND_TIMEOUT_MS = 10_000;

/** RFC 5322 From with a display name; non-ASCII names are MIME-encoded (SES rejects raw UTF-8 there). */
export function formatFrom(name: string, email: string): string {
  if (!name) return email;
  if (/^[\x20-\x7e]*$/.test(name)) return `"${name.replace(/["\\]/g, '\\$&')}" <${email}>`;
  return `=?UTF-8?B?${Buffer.from(name, 'utf8').toString('base64')}?= <${email}>`;
}

export function sesClient(opts: {
  region: string;
  credentials?: { accessKeyId: string; secretAccessKey: string };
}): SESv2Client {
  return new SESv2Client({ region: opts.region, credentials: opts.credentials });
}

/**
 * Amazon SES (v2 API). No click or open tracking: SES only adds those through a configuration set,
 * and we don't use one — tracking would rewrite sign-in links through a redirect domain and drop
 * the `#token=` fragment.
 */
export function sesMailer(opts: { client: SesSender; fromEmail: string; fromName: string }): Mailer {
  const from = formatFrom(opts.fromName, opts.fromEmail);
  return {
    async send({ to, subject, text, html }) {
      const command = new SendEmailCommand({
        FromEmailAddress: from,
        Destination: { ToAddresses: [to] },
        Content: {
          Simple: {
            Subject: { Data: subject, Charset: 'UTF-8' },
            Body: {
              Text: { Data: text, Charset: 'UTF-8' },
              Html: { Data: html, Charset: 'UTF-8' },
            },
          },
        },
      });
      try {
        await opts.client.send(command, { abortSignal: AbortSignal.timeout(SEND_TIMEOUT_MS) });
      } catch (err) {
        const e = err as Error;
        throw new Error(`SES SendEmail failed: ${e.name}: ${e.message}`.slice(0, 300), { cause: err });
      }
    },
  };
}

/** Dev fallback when EMAIL_TRANSPORT is console: prints the email (including links) to the console. */
export function consoleMailer(): Mailer {
  return {
    async send({ to, subject, text }) {
      console.log(`\n[mail] ── to: ${to}\n[mail] subject: ${subject}\n${text.replace(/^/gm, '[mail] ')}\n`);
    },
  };
}
