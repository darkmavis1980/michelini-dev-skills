// Example tests for mailer.ts (Vitest). A fake SES client records the command, so no AWS call is made.
import { describe, expect, it } from 'vitest';
import type { SendEmailCommand } from '@aws-sdk/client-sesv2';
import { formatFrom, sesMailer, type SesSender } from './mailer.js';

class FakeSes implements SesSender {
  sent: { command: SendEmailCommand; abortSignal?: AbortSignal }[] = [];
  failWith: Error | null = null;
  async send(command: SendEmailCommand, options?: { abortSignal?: AbortSignal }) {
    if (this.failWith) throw this.failWith;
    this.sent.push({ command, abortSignal: options?.abortSignal });
    return {};
  }
}

const message = { to: 'customer@example.com', subject: 'Sign in — shop', text: 'Hello', html: '<p>Hello</p>' };

describe('sesMailer', () => {
  it('sends one UTF-8 email with text and HTML parts, from the display name', async () => {
    const ses = new FakeSes();
    await sesMailer({ client: ses, fromEmail: 'shop@example.com', fromName: 'Example Photography' }).send(message);

    expect(ses.sent).toHaveLength(1);
    const { command, abortSignal } = ses.sent[0]!;
    expect(command.input).toEqual({
      FromEmailAddress: '"Example Photography" <shop@example.com>',
      Destination: { ToAddresses: ['customer@example.com'] },
      Content: {
        Simple: {
          Subject: { Data: 'Sign in — shop', Charset: 'UTF-8' },
          Body: { Text: { Data: 'Hello', Charset: 'UTF-8' }, Html: { Data: '<p>Hello</p>', Charset: 'UTF-8' } },
        },
      },
    });
    // No configuration set: SES only adds click / open tracking through one.
    expect(command.input).not.toHaveProperty('ConfigurationSetName');
    expect(abortSignal).toBeInstanceOf(AbortSignal);
  });

  it('wraps SES errors so callers see what failed', async () => {
    const ses = new FakeSes();
    ses.failWith = Object.assign(new Error('Email address is not verified.'), { name: 'MessageRejected' });
    const mailer = sesMailer({ client: ses, fromEmail: 'shop@example.com', fromName: 'Shop' });
    await expect(mailer.send(message)).rejects.toThrow(
      'SES SendEmail failed: MessageRejected: Email address is not verified.',
    );
  });
});

describe('formatFrom', () => {
  it('quotes ASCII names and escapes quotes and backslashes', () => {
    expect(formatFrom('A "B" \\ C', 'a@example.com')).toBe('"A \\"B\\" \\\\ C" <a@example.com>');
  });

  it('MIME-encodes non-ASCII names', () => {
    expect(formatFrom('Fotografía', 'a@example.com')).toBe(
      `=?UTF-8?B?${Buffer.from('Fotografía').toString('base64')}?= <a@example.com>`,
    );
  });

  it('uses the bare address without a name', () => {
    expect(formatFrom('', 'a@example.com')).toBe('a@example.com');
  });
});
