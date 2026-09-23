# CUFSC Ice Time

Booking and administration system for Cornell University Figure Skating Club ice sessions. Members can use the dashboard’s Attendees tab to see upcoming sessions and signup-ordered names.

## Architecture

- Next.js 16 and React 19 provide the browser UI.
- Supabase Auth handles Google OAuth.
- Supabase Postgres stores members, tiers, sessions, bookings, approvals, and the credit audit log.
- PostgreSQL RPC functions are the authoritative business-logic and authorization boundary.
- A Supabase Edge Function sends new-request alerts, account/session approval confirmations, and admin booking-removal emails through Resend.
- Vercel hosts the frontend at `https://cufscice.vercel.app`.

Project guides:

- [DESIGN.md](./DESIGN.md) — architecture, data model, authorization, and notification behavior
- [HANDOFF.md](./HANDOFF.md) — production operations, deployment, and recovery
- [CONTRIBUTING.md](./CONTRIBUTING.md) — complete workflow for human and AI-assisted changes
- [AGENTS.md](./AGENTS.md) — repository rules automatically consumed by compatible AI coding tools

## Local setup

Requirements:

- Node.js 20 or newer
- Docker Desktop or another Docker-compatible runtime
- Supabase CLI access to the project

Create `.env.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://dtdyvpjmavurynbccjei.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<Supabase publishable key>
```

Legacy JWT-based `anon` and `service_role` API keys are not supported. Use a
publishable key in browser code and a secret key only in trusted backend code.

Install and run:

```bash
npm ci
npm run dev
```

Useful checks:

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

Add `http://localhost:3000/auth/callback` to the Supabase Auth redirect allowlist before testing local Google login.

Admins can remove individual bookings with credit refunds and email notifications. Admin Tools also includes an immediate one-credit contingency reset; temporary accounts receive zero, and the next weekly reset restores normal tier allowances. The dashboard highlights booking rules and shows the countdown to no-credit booking in calendar and list views.

## Database workflow

The committed files under `supabase/migrations/` are the source of truth. Do not edit production functions or policies directly in the Dashboard. Create and test a migration locally, review `supabase db push --dry-run`, and only then apply it to the linked project.

The local schema-only inspection dump at `supabase/schema.sql` is intentionally ignored and is not documentation or a source of truth; database webhook definitions in dumps can contain credentials.

## Changing the project

Start with [CONTRIBUTING.md](./CONTRIBUTING.md), whether you are editing the project manually or with an AI coding assistant. It explains which files to change, required checks, database and Edge Function workflows, deployment authorization, and the documentation that must remain synchronized.

AI tools should read [AGENTS.md](./AGENTS.md) before making changes. Always review AI-generated code and migrations before committing or deploying them.

## Entire-session cancellation

Admin Sessions includes **Cancel Session**, with a confirmation naming the session. It cancels all active bookings, refunds only charged credits, and emails each booked member that the whole session was cancelled. Each email has a unique notification ID in `booking_removal_notifications`. Existing cancelled bookings are unaffected, and repeated cancellation does not duplicate refunds or notifications. Pending approval requests are denied. The session remains visible as Cancelled with zero capacity and can be restored by an admin within seven days of cancellation and before its start; this is distinct from permanent deletion.

## Restoring cancelled sessions

Admin Sessions → **Restore Session** opens a popup offering **Reopen empty** or **Restore previous bookings and pending requests**. Restoration is allowed for seven days after cancellation, and only before the session starts. Empty restoration leaves refunds intact. Full restoration uses the cancellation notification logs and original booking IDs, preserves signup times, and deducts only previously refunded credits. If a member has spent the refund or logged records are missing, restoration stops atomically rather than producing negative balances or partial bookings. Repeating a successful restoration does nothing.

New cancellations snapshot the original capacity, label, and pending-request notes. For older cancellations, the popup requires an explicit original capacity because notification logs never stored it; original request notes may be unavailable. Deleted legacy booking records cannot be reconstructed from names or email addresses. Restored bookings receive new IDs so later cancellations retain distinct notification histories. Superseded cancellation notices remain in the audit history but the email worker skips them. Restoration does not send member emails.
