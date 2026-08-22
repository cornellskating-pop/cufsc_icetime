# CUFSC Ice Time — Operations and Handoff

This guide covers routine administration, deployment, and recovery. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the full human and AI-assisted development workflow.

## Services

| Service | Responsibility |
|---|---|
| GitHub | Source code and migration history |
| Vercel | Frontend hosting and automatic deployments |
| Supabase | PostgreSQL, Google OAuth, RLS, RPCs, Vault, cron, and Edge Functions |
| Resend | Approval-notification email delivery |

Production frontend: `https://cufscice.vercel.app`

Supabase project reference: `dtdyvpjmavurynbccjei`

## Routine admin work

- Add or edit a member: `/admin/users`
- Add, edit, or remove a session: `/admin/sessions`
- Review attendance: `/admin/bookings`
- Approve or deny requests: `/admin/approvals`
- Run the weekly credit reset manually: `/admin/tools`

Admin UI visibility is checked in the browser, but PostgreSQL RPC authorization and RLS are the security boundary.

## Developer setup

Install Node.js 20+, Git, and Docker Desktop. Then:

```bash
git clone https://github.com/cornellskating-pop/cufsc_icetime.git
cd cufsc_icetime
npm ci
npx supabase login
npx supabase link --project-ref dtdyvpjmavurynbccjei
```

Create `.env.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://dtdyvpjmavurynbccjei.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Do not use the legacy JWT-based `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

Add `http://localhost:3000/auth/callback` under Supabase Authentication → URL Configuration → Redirect URLs.

Run:

```bash
npm run dev
```

## Required checks

Before proposing a deployment:

```bash
npm run lint
npm run build
npx supabase start
npx supabase db reset
docker exec -i supabase_db_ice-booking \
  psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < supabase/tests/hardening_smoke.sql
npx supabase stop
```

The smoke test runs in a transaction and rolls back its test records.

## Database changes

Database changes must be committed as timestamped files in `supabase/migrations/`. Avoid direct production edits in the SQL Editor because they create drift between Git and Supabase.

Normal workflow:

```bash
npx supabase migration new short_description
# edit the generated SQL
npx supabase db reset
npx supabase db push --dry-run
```

Only run `npx supabase db push` after review and explicit production approval.

### Initial baseline

`20260726090000_remote_schema_baseline.sql` represents the database as it existed before migrations were brought into Git. It must be marked as already applied on the existing production project before the first push:

```bash
npx supabase migration repair --status applied 20260726090000
npx supabase migration list
npx supabase db push --dry-run
```

The dry run must show only migrations after the baseline. Never push the baseline onto the existing database.

## Approval notification configuration

The notification webhook uses a shared random value in two secure locations:

1. Supabase Vault, named `notify_admins_webhook_secret`
2. Edge Function secret `NOTIFY_WEBHOOK_SECRET`

The values must match. Do not put the value in Git, chat, command history, or migration SQL.

Other Edge Function variables:

| Variable | Purpose |
|---|---|
| `RESEND_API_KEY` | Resend authentication |
| `SUPABASE_SECRET_KEYS` | Supabase-managed JSON map; the function reads its `default` secret key |
| `NOTIFY_EMAIL` | Optional comma-separated override recipients for new-request alerts; otherwise all admin emails are used |
| `FROM_EMAIL` | Verified Resend sender |
| `APP_URL` | Defaults to `https://cufscice.vercel.app` |

Deploy the function separately:

```bash
npx supabase functions deploy notify-admins --no-verify-jwt
```

The function authenticates database webhooks with `x-webhook-secret`; Supabase’s legacy JWT verification is intentionally disabled for this function.

Notification behavior:

| Event | Recipient | Message |
|---|---|---|
| Any new approval request | `NOTIFY_EMAIL`, or all admins when unset | Link to `/admin/approvals` |
| `NEW_USER` changes to `APPROVED` | The requester's email | Account approved and link to the booking app |
| Denial, session approval, or unrelated update | None | No email |

Both messages use `FROM_EMAIL`. If it is unset, the code fallback is `CUFSC Booking <onboarding@resend.dev>`. Configure a Resend-verified sender before relying on a club or Cornell-domain address.

## Deployment order

For an ordinary frontend-only change:

```bash
git push
```

Vercel deploys the pushed branch automatically.

For a change that includes both an Edge Function and a database trigger or migration:

1. Confirm a current Supabase backup is available.
2. Configure the matching Vault and Edge Function webhook secrets.
3. Confirm the Supabase-managed `SUPABASE_SECRET_KEYS` default secret is available.
4. Run `npx supabase migration list`; local and remote history must match except for the intended new migration.
5. Run and review `npx supabase db push --dry-run`; stop if it lists unrelated migrations.
6. Deploy the compatible Edge Function before enabling a trigger that calls it.
7. Apply the reviewed migration with `npx supabase db push` only with explicit production authorization.
8. Run the production verification checklist and inspect Supabase and Resend logs.
9. Commit and push the exact deployed source and migration so GitHub and production do not drift.

The weekly reset cron job must use schedule `30 20,21 * * 0` and execute
`select private.scheduled_weekly_reset_credits();`. Supabase cron schedules
use UTC, so the job runs at both possible UTC equivalents of 4:30 PM Eastern.
The worker checks `America/New_York` and performs the reset only for the
invocation that is actually Sunday at 4:30 PM, keeping the schedule correct
across daylight-saving transitions. `public.admin_weekly_reset_credits()`
remains the authenticated manual admin RPC.

Approval records remain in the database if notification delivery fails. Because webhook delivery is asynchronous, approval success does not guarantee email delivery; verify failures in the services listed under Recovery.

## Production verification

- Existing member can sign in.
- Non-member can submit one access request.
- Member cannot enter `/admin`.
- Admin can open every admin page.
- Unreleased session cannot be booked through the RPC.
- Normal booking deducts one credit.
- Grace-period booking deducts no credit.
- Cancelling a charged booking at least 30 minutes before start refunds one credit.
- Cancelling a free or approved booking never creates a credit.
- Capacity cannot be exceeded by concurrent requests.
- Approval notification arrives and links to `https://cufscice.vercel.app/admin/approvals`.
- An approved new member receives an email linking to the booking app.
- Vercel and Supabase logs show no new errors.

## Recovery

If the frontend deployment fails, use Vercel’s previous deployment while leaving the database migration in place. The hardened RPCs retain the existing frontend method names.

If the database migration fails, PostgreSQL rolls it back because it is transactional. Do not use `db reset --linked`.

If notification delivery fails, approval requests are still stored. Inspect:

- Supabase Edge Functions → `notify-admins` → Logs
- Supabase Database → Webhook/pg_net logs
- Resend → Logs

If a secret is exposed, revoke or replace it and inspect logs. Never commit a raw schema dump until its webhook headers have been reviewed and redacted.
