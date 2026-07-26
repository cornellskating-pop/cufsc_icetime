# CUFSC Ice Time

Booking and administration system for Cornell University Figure Skating Club ice sessions.

## Architecture

- Next.js 16 and React 19 provide the browser UI.
- Supabase Auth handles Google OAuth.
- Supabase Postgres stores members, tiers, sessions, bookings, approvals, and the credit audit log.
- PostgreSQL RPC functions are the authoritative business-logic and authorization boundary.
- A Supabase Edge Function sends approval notifications through Resend.
- Vercel hosts the frontend at `https://cufscice.vercel.app`.

See [DESIGN.md](./DESIGN.md) for the technical design and [HANDOFF.md](./HANDOFF.md) for operations and deployment.

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
npm install
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

## Database workflow

The committed files under `supabase/migrations/` are the source of truth. Do not edit production functions or policies directly in the Dashboard. Create and test a migration locally, review `supabase db push --dry-run`, and only then apply it to the linked project.

The schema-only inspection dump at `supabase/schema.sql` is intentionally ignored because database webhook definitions can contain credentials.
