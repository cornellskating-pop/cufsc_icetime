# Contributing to CUFSC Ice Time

This is the complete change guide for maintainers, contributors, and anyone using an AI coding assistant. Read it with [DESIGN.md](./DESIGN.md) and [HANDOFF.md](./HANDOFF.md) before changing production-facing behavior.

## Sources of truth

| Concern | Source of truth |
|---|---|
| Frontend behavior | `app/` and `lib/` |
| Database schema and behavior | Ordered files in `supabase/migrations/` |
| Edge Function behavior | `supabase/functions/` |
| Local database fixtures | `supabase/seed.sql` |
| Automated database checks | `supabase/tests/` |
| Architecture | `DESIGN.md` |
| Production operations | `HANDOFF.md` |

`supabase/schema.sql` is an ignored local inspection dump. Do not edit, commit, cite, or treat it as current documentation. Never edit an already-applied migration; add a new timestamped migration instead.

## Set up a development copy

Requirements: Node.js 20+, Git, Docker Desktop or a compatible runtime, and Supabase CLI access when working with the linked project.

```bash
git clone https://github.com/cornellskating-pop/cufsc_icetime.git
cd cufsc_icetime
npm ci
```

Create an uncommitted `.env.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://dtdyvpjmavurynbccjei.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Never place service keys, Resend keys, webhook secrets, access tokens, or real member data in Git, prompts, logs, screenshots, fixtures, or migrations.

Run the frontend with `npm run dev`. For local Google login, add `http://localhost:3000/auth/callback` to the Supabase Auth redirect allowlist.

## Make a change

1. Pull the latest `main` and create a focused branch.
2. Read the relevant UI, RPC, migration, tests, and documentation before editing.
3. Keep authorization and business rules in PostgreSQL RPCs, RLS, constraints, and grants—not only in browser code.
4. Preserve unrelated changes and avoid broad formatting rewrites.
5. Add or update tests in proportion to the behavior and risk.
6. Update every affected guide in the same commit.
7. Run the required checks, review the diff, and use the pull-request checklist.

### File routing

- UI, routing, or copy: `app/`, `lib/`, and possibly `app/globals.css`.
- Database logic, permissions, RLS, tables, triggers, or cron helpers: a new file in `supabase/migrations/` plus relevant SQL tests.
- Email or webhook behavior: `supabase/functions/`, a migration when the trigger changes, and the notification sections of `DESIGN.md` and `HANDOFF.md`.
- Dependencies or build behavior: `package.json`, `package-lock.json`, and setup documentation.
- Production procedures or configuration: `HANDOFF.md`.
- Architecture, data flow, or security boundaries: `DESIGN.md`.

## Use an AI coding assistant safely

Compatible AI tools should automatically read [AGENTS.md](./AGENTS.md). If a tool does not, tell it to read `AGENTS.md`, `CONTRIBUTING.md`, `DESIGN.md`, and `HANDOFF.md` before editing.

A useful request includes the desired outcome, affected users, constraints, and whether production deployment is authorized. Ask the tool to inspect existing behavior first, preserve unrelated work, implement the smallest coherent change, run checks, and summarize changed files and deployment requirements.

The human operator remains responsible for reviewing:

- Authentication, authorization, RLS, grants, and `SECURITY DEFINER` functions.
- Credit, capacity, booking, cancellation, and approval transactions.
- Generated SQL and the exact output of `supabase db push --dry-run`.
- Secret handling, email recipients, external service calls, and production changes.
- The final diff, tests, documentation, commit, and deployment result.

Do not ask an AI tool to paste secret values into code or chat. Do not let it deploy, push migrations, email users, delete data, or change external configuration unless an authorized maintainer explicitly approves that action and its exact scope.

## Required checks

For every code change:

```bash
npm run lint
npm run build
```

For database changes, also run the local stack and smoke test:

```bash
npx supabase start
npx supabase db reset
docker exec -i supabase_db_ice-booking \
  psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < supabase/tests/hardening_smoke.sql
npx supabase stop
```

Before an authorized production database deployment:

```bash
npx supabase migration list
npx supabase db push --dry-run
```

The dry run must list only the intended new migrations. Do not use `db reset --linked`.

## Database and Edge Function workflow

Create database changes with `npx supabase migration new short_description`. Make migrations transactional where supported, set fixed search paths on security-definer functions, use explicit grants, and consider concurrent requests and row locking.

Edge Functions are deployed separately from Vercel and database migrations. When a trigger depends on new function behavior:

1. Deploy the backward-compatible Edge Function.
2. Apply the reviewed trigger migration.
3. Verify the event in Supabase Function, database webhook, and provider logs.

See [HANDOFF.md](./HANDOFF.md) for exact production commands, ordering, verification, and recovery.

## Documentation definition of done

Update documentation in the same change whenever behavior, configuration, architecture, setup, testing, or deployment changes:

- `README.md` for the project overview, quick start, and guide links.
- `DESIGN.md` for current architecture, data flow, security boundaries, and data model.
- `HANDOFF.md` for production configuration, deployment, verification, and recovery.
- `CONTRIBUTING.md` and `AGENTS.md` for maintainer or AI workflow changes.
- `.github/pull_request_template.md` when the review checklist changes.

Historical migrations are records of what was applied; do not rewrite them to make their comments look current. Add a new migration and document the resulting current behavior instead.

## Commit and review

Keep commits focused and use an imperative summary such as `Notify users when access is approved`. Never commit `.env*`, local dumps, backups, build output, or credentials. Confirm `git status` contains only intended files before committing and pushing.
