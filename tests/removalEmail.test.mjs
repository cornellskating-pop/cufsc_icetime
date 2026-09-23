import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

const source = fs.readFileSync('supabase/functions/notify-admins/index.ts', 'utf8').replace(/^import .*\n/, '');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText;
function harness({ sent = false, emailFails = false, sessionCancelled = false, superseded = false } = {}) {
  let handler;
  const calls = [];
  const notice = { superseded_at: superseded ? '2026-09-22T00:00:00Z' : null, reason: sessionCancelled ? 'session_cancelled' : 'booking_removed', id: 'test-notice', recipient_email: 'member@example.test', member_name: 'Test Member', start_time: '2026-10-01T00:00:00Z', end_time: '2026-10-01T01:00:00Z', refunded: true, sent_at: sent ? '2026-09-21T00:00:00Z' : null };
  vm.runInNewContext(code, {
    Request, Response, console: { error() {} },
    Deno: { env: { get: key => ({ SUPABASE_SECRET_KEYS: '{"default":"fake-test-key"}', NOTIFY_WEBHOOK_SECRET: 'test-secret', RESEND_API_KEY: 'fake-test-key', SUPABASE_URL: 'https://example.test' })[key] }, serve: fn => { handler = fn; } },
    createClient: () => ({ from: table => {
      assert.equal(table, 'booking_removal_notifications');
      return {
        select: () => ({ eq: (column, id) => { assert.equal(id, 'test-notice'); return { single: async () => ({ data: notice, error: null }) }; } }),
        update: value => ({ eq: async () => { calls.push({ update: value }); return { error: null }; } }),
      };
    } }),
    fetch: async (url, options) => { calls.push({ url, options }); return new Response('', { status: emailFails ? 500 : 200 }); },
  });
  return { calls, run: (secret = 'test-secret') => handler(new Request('https://example.test', { method: 'POST', headers: { 'x-webhook-secret': secret }, body: JSON.stringify({ table: 'booking_removal_notifications', type: 'INSERT', record: { id: 'test-notice', recipient_email: 'forged@example.test' } }) })) };
}
test('removal email uses authoritative recipient, refund details and idempotency key', async () => {
  const h = harness();
  assert.equal((await h.run()).status, 200);
  const email = JSON.parse(h.calls[0].options.body);
  assert.deepEqual(email.to, ['member@example.test']);
  assert.match(email.text, /credit.*returned/);
  assert.equal(h.calls[0].options.headers['Idempotency-Key'], 'booking-removal/test-notice');
  assert.ok(h.calls[1].update.sent_at);
});
test('already sent notifications and unauthorized requests do not send email', async () => {
  const duplicate = harness({ sent: true });
  assert.equal((await duplicate.run()).status, 200);
  assert.equal(duplicate.calls.length, 0);
  const denied = harness();
  assert.equal((await denied.run('incorrect')).status, 401);
  assert.equal(denied.calls.length, 0);
});
test('delivery failure leaves notification pending', async () => {
  const h = harness({ emailFails: true });
  assert.equal((await h.run()).status, 500);
  assert.equal(h.calls.length, 1);
});

test('session cancellation email clearly identifies the whole-session cancellation', async () => {
  const h = harness({ sessionCancelled: true });
  assert.equal((await h.run()).status, 200);
  const email = JSON.parse(h.calls[0].options.body);
  assert.equal(email.subject, 'Your CUFSC ice session was cancelled');
  assert.match(email.text, /session has been cancelled/);
});

test('undone cancellations do not send outdated cancellation emails', async () => {
  const h = harness({ sessionCancelled: true, superseded: true });
  assert.equal((await h.run()).status, 200);
  assert.equal(h.calls.length, 0);
});
