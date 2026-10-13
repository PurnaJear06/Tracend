// A minimal SMTP client for transactional mail over implicit TLS (port 465).
// Edge Functions cannot open ports 25 or 587, and every mainstream provider
// (Gmail, Resend, Brevo, Zoho) accepts 465, so the provider is a setting.

export interface SmtpConfig {
  host: string;
  user: string;
  password: string;
}

export interface Mail {
  from: string; // "Name <address>" or "address"
  to: string;
  subject: string;
  text: string;
  html: string;
  headers?: Readonly<Record<string, string>>;
}

export interface SmtpConnection {
  read(buffer: Uint8Array): Promise<number | null>;
  write(data: Uint8Array): Promise<number>;
  close(): void;
}

export type Connect = (host: string, port: number) => Promise<SmtpConnection>;

const connectTls: Connect = (host, port) => Deno.connectTls({ hostname: host, port });

export class SmtpError extends Error {
  constructor(readonly stage: string, readonly code: number) {
    super(`smtp_${stage}_${code}`);
    this.name = "SmtpError";
  }
}

const ADDRESS = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/;

/** The bare address inside "Name <address>", or the whole value. */
export function addressOf(mailbox: string): string {
  const match = mailbox.match(/<([^<>]+)>\s*$/);
  const address = (match ? match[1] : mailbox).trim();
  if (!ADDRESS.test(address)) throw new Error("smtp_bad_address");
  return address;
}

function headerValue(value: string): string {
  if (/[\r\n]/.test(value)) throw new Error("smtp_bad_header");
  return value;
}

/** RFC 2047 encoding for header text that is not plain ASCII. */
function encodeWord(text: string): string {
  if (/^[\x20-\x7e]*$/.test(text)) return text;
  return `=?UTF-8?B?${base64(new TextEncoder().encode(text))}?=`;
}

function encodeMailbox(mailbox: string): string {
  const match = mailbox.match(/^\s*(.*?)\s*<([^<>]+)>\s*$/);
  if (!match || !match[1]) return addressOf(mailbox);
  const name = match[1].replace(/^"|"$/g, "");
  const display = /^[\x20-\x7e]*$/.test(name)
    ? `"${name.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`
    : encodeWord(name);
  return `${display} <${addressOf(mailbox)}>`;
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** Base64 body wrapped at 76 characters: no long lines and no lone dots to escape. */
function base64Body(text: string): string {
  return base64(new TextEncoder().encode(text)).replace(/.{1,76}/g, "$&\r\n");
}

export function buildMessage(mail: Mail, now = new Date()): string {
  const from = addressOf(mail.from);
  const boundary = `tracend-${crypto.randomUUID()}`;
  const domain = from.split("@")[1];
  const headers: Array<[string, string]> = [
    ["From", encodeMailbox(mail.from)],
    ["To", encodeMailbox(mail.to)],
    ["Subject", encodeWord(headerValue(mail.subject))],
    ["Date", now.toUTCString().replace("GMT", "+0000")],
    ["Message-ID", `<${crypto.randomUUID()}@${domain}>`],
    ["MIME-Version", "1.0"],
    ...Object.entries(mail.headers ?? {}).map(([k, v]) =>
      [headerValue(k), headerValue(v)] as [string, string]
    ),
    ["Content-Type", `multipart/alternative; boundary="${boundary}"`],
  ];
  const part = (type: string, body: string) =>
    `--${boundary}\r\nContent-Type: ${type}; charset=utf-8\r\n` +
    `Content-Transfer-Encoding: base64\r\n\r\n${base64Body(body)}`;
  return headers.map(([k, v]) => `${k}: ${v}`).join("\r\n") + "\r\n\r\n" +
    part("text/plain", mail.text) + part("text/html", mail.html) + `--${boundary}--\r\n`;
}

class Session {
  private buffer = "";
  private readonly decoder = new TextDecoder();
  private readonly encoder = new TextEncoder();

  constructor(private readonly conn: SmtpConnection) {}

  private async line(): Promise<string> {
    while (!this.buffer.includes("\r\n")) {
      const chunk = new Uint8Array(4096);
      const read = await this.conn.read(chunk);
      if (read === null) throw new SmtpError("closed", 0);
      this.buffer += this.decoder.decode(chunk.subarray(0, read), { stream: true });
    }
    const end = this.buffer.indexOf("\r\n");
    const text = this.buffer.slice(0, end);
    this.buffer = this.buffer.slice(end + 2);
    return text;
  }

  /** Reads one (possibly multi-line) reply and checks its code. */
  async expect(stage: string, ...codes: number[]): Promise<void> {
    let text = await this.line();
    while (text.length > 3 && text[3] === "-") text = await this.line();
    const code = Number(text.slice(0, 3));
    if (!codes.includes(code)) throw new SmtpError(stage, Number.isFinite(code) ? code : 0);
  }

  async send(command: string): Promise<void> {
    const bytes = this.encoder.encode(command + "\r\n");
    let written = 0;
    while (written < bytes.length) written += await this.conn.write(bytes.subarray(written));
  }
}

/** Sends one message. Throws SmtpError (never with credentials or addresses in it). */
export async function sendMail(
  config: SmtpConfig,
  mail: Mail,
  options: { connect?: Connect; timeoutMs?: number } = {},
): Promise<void> {
  const message = buildMessage(mail);
  const from = addressOf(mail.from);
  const to = addressOf(mail.to);
  const timeoutMs = options.timeoutMs ?? 15_000;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const conn = await Promise.race([
    (options.connect ?? connectTls)(config.host, 465),
    new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new SmtpError("connect", 0)), timeoutMs);
    }),
  ]).catch((error) => {
    throw error instanceof SmtpError ? error : new SmtpError("connect", 0);
  }).finally(() => clearTimeout(timer));
  timer = setTimeout(() => conn.close(), timeoutMs);
  const smtp = new Session(conn);
  try {
    await smtp.expect("greeting", 220);
    await smtp.send("EHLO tracend");
    await smtp.expect("ehlo", 250);
    await smtp.send(
      `AUTH PLAIN ${base64(new TextEncoder().encode(`\0${config.user}\0${config.password}`))}`,
    );
    await smtp.expect("auth", 235);
    await smtp.send(`MAIL FROM:<${from}>`);
    await smtp.expect("mail_from", 250);
    await smtp.send(`RCPT TO:<${to}>`);
    await smtp.expect("rcpt_to", 250, 251);
    await smtp.send("DATA");
    await smtp.expect("data", 354);
    await smtp.send(message + ".");
    await smtp.expect("message", 250);
    await smtp.send("QUIT");
  } catch (error) {
    if (error instanceof SmtpError) throw error;
    throw new SmtpError("connection", 0);
  } finally {
    clearTimeout(timer);
    try {
      conn.close();
    } catch {
      // already closed by the timeout or the server
    }
  }
}
