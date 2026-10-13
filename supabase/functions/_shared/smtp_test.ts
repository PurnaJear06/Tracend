import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { addressOf, buildMessage, sendMail, SmtpError } from "./smtp.ts";

/** A scripted server: replies once per command, records what the client wrote. */
function fakeServer(replies: Record<string, string>) {
  const written: string[] = [];
  const pending: Uint8Array[] = [new TextEncoder().encode("220 smtp.test ready\r\n")];
  let waiting: (() => void) | null = null;
  let closed = false;
  let inData = false;
  let buffer = "";
  const conn = {
    read(target: Uint8Array): Promise<number | null> {
      const take = () => {
        const next = pending.shift()!;
        target.set(next);
        return next.length;
      };
      if (pending.length) return Promise.resolve(take());
      if (closed) return Promise.resolve(null);
      return new Promise<number | null>((resolve) => {
        waiting = () => resolve(pending.length ? take() : null);
      });
    },
    write(data: Uint8Array): Promise<number> {
      buffer += new TextDecoder().decode(data);
      while (true) {
        if (inData) {
          const end = buffer.indexOf("\r\n.\r\n");
          if (end < 0) break;
          written.push(buffer.slice(0, end));
          buffer = buffer.slice(end + 5);
          inData = false;
          reply(replies.MESSAGE ?? "250 queued");
          continue;
        }
        const end = buffer.indexOf("\r\n");
        if (end < 0) break;
        const line = buffer.slice(0, end);
        buffer = buffer.slice(end + 2);
        written.push(line);
        const verb = line.split(/[ :]/)[0];
        if (verb === "DATA") inData = true;
        const defaults: Record<string, string> = {
          EHLO: "250-smtp.test\r\n250-AUTH PLAIN\r\n250 SIZE 1000000",
          AUTH: "235 ok",
          MAIL: "250 ok",
          RCPT: "250 ok",
          DATA: "354 go ahead",
          QUIT: "221 bye",
        };
        reply(replies[verb] ?? defaults[verb] ?? "500 unknown");
      }
      return Promise.resolve(data.length);
    },
    close() {
      closed = true;
      waiting?.();
    },
  };
  function reply(text: string) {
    pending.push(new TextEncoder().encode(text + "\r\n"));
    const wake = waiting;
    waiting = null;
    wake?.();
  }
  return { conn, written, isClosed: () => closed };
}

const mail = {
  from: "Tracend <team@tracend.test>",
  to: "runner@example.test",
  subject: "Confirm your place on the Tracend beta",
  text: "Hello\n.\nline starting with a dot",
  html: "<p>Hello</p>",
  headers: { "List-Unsubscribe": "<https://api.test/u?token=abc>" },
};
const config = { host: "smtp.test", user: "team@tracend.test", password: "app pass" };

Deno.test("sends one message through the full SMTP conversation", async () => {
  const server = fakeServer({});
  await sendMail(config, mail, { connect: () => Promise.resolve(server.conn) });
  const [ehlo, auth, from, rcpt, data, message, quit] = server.written;
  assertEquals(ehlo, "EHLO tracend");
  assertEquals(auth, `AUTH PLAIN ${btoa("\0team@tracend.test\0app pass")}`);
  assertEquals(from, "MAIL FROM:<team@tracend.test>");
  assertEquals(rcpt, "RCPT TO:<runner@example.test>");
  assertEquals(data, "DATA");
  assert(message.includes('From: "Tracend" <team@tracend.test>'));
  assert(message.includes("List-Unsubscribe: <https://api.test/u?token=abc>"));
  assertEquals(quit, "QUIT");
  assert(server.isClosed());
});

Deno.test("a refused login fails with the stage and code, never the password", async () => {
  const server = fakeServer({ AUTH: "535 5.7.8 bad credentials" });
  const error = await assertRejects(
    () => sendMail(config, mail, { connect: () => Promise.resolve(server.conn) }),
    SmtpError,
  );
  assertEquals(error.message, "smtp_auth_535");
  assert(!error.message.includes("app pass"));
  assert(server.isClosed());
});

Deno.test("a refused recipient stops before any message is sent", async () => {
  const server = fakeServer({ RCPT: "550 no such user" });
  await assertRejects(
    () => sendMail(config, mail, { connect: () => Promise.resolve(server.conn) }),
    SmtpError,
    "smtp_rcpt_to_550",
  );
  assert(!server.written.includes("DATA"));
});

Deno.test("a server that never answers times out", async () => {
  let hangUp = () => {};
  const silent = {
    read: () => new Promise<number | null>((resolve) => (hangUp = () => resolve(null))),
    write: (data: Uint8Array) => Promise.resolve(data.length),
    close: () => hangUp(),
  };
  await assertRejects(
    () => sendMail(config, mail, { connect: () => Promise.resolve(silent), timeoutMs: 30 }),
    SmtpError,
    "smtp_closed_0",
  );
});

Deno.test("a connection that cannot open fails cleanly", async () => {
  await assertRejects(
    () => sendMail(config, mail, { connect: () => Promise.reject(new Error("refused")) }),
    SmtpError,
    "smtp_connect_0",
  );
});

Deno.test("the message is base64 MIME with no bare dot lines and no header injection", () => {
  const message = buildMessage(mail, new Date("2026-10-13T10:00:00Z"));
  assert(!message.split("\r\n").some((line) => line === "."));
  assert(message.includes("Content-Transfer-Encoding: base64"));
  assert(message.includes("Date: Tue, 13 Oct 2026 10:00:00 +0000"));
  assert(message.split("\r\n").every((line) => line.length <= 998));
  const injected = { ...mail, subject: "Hi\r\nBcc: someone@evil.test" };
  let threw = false;
  try {
    buildMessage(injected);
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("non-ASCII subjects and names are encoded", () => {
  const message = buildMessage({ ...mail, from: "Tracénd <team@tracend.test>", subject: "Café" });
  assert(message.includes("Subject: =?UTF-8?B?"));
  assert(message.includes("From: =?UTF-8?B?"));
});

Deno.test("addresses are taken from mailboxes and validated", () => {
  assertEquals(addressOf("Tracend <team@tracend.test>"), "team@tracend.test");
  assertEquals(addressOf("runner@example.test"), "runner@example.test");
  let threw = false;
  try {
    addressOf("not an address");
  } catch {
    threw = true;
  }
  assert(threw);
});
