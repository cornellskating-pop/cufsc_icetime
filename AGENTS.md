# AI Maintainer Instructions

These instructions apply to the entire repository and are intended for AI coding agents and assistants.

## Before editing

1. Read `README.md`, `CONTRIBUTING.md`, `DESIGN.md`, and `HANDOFF.md` completely.
2. Inspect the relevant implementation, migrations, tests, and current Git status.
3. Treat `supabase/migrations/` as the database source of truth. Ignore `supabase/schema.sql`; it is a local inspection dump.
4. Preserve user changes and unrelated work. Do not rewrite or remove them.

## Implementation rules

- Keep browser code thin. Authorization and transactional booking rules belong in PostgreSQL RPCs, RLS, constraints, and grants.
- Never edit an applied migration. Add a timestamped migration for every database change.
- Security-definer functions must use a fixed search path and enforce authorization internally.
- Consider concurrency, row locking, credit accounting, capacity, release times, and cancellation refunds when changing booking logic.
- Keep secrets and real user data out of source, tool output, prompts, fixtures, migrations, and documentation.
- Do not replace publishable and secret Supabase keys with legacy JWT-based keys.
- Do not deploy, push migrations, modify external services, send messages, or delete data without explicit authorization from the user or maintainer.

## Verification

- Run `npm run lint` and `npm run build` for code changes.
- For database changes, run the local reset and `supabase/tests/hardening_smoke.sql` workflow in `CONTRIBUTING.md` when Docker is available.
- Before any authorized production migration, run `supabase migration list` and `supabase db push --dry-run`. Stop if unrelated migrations appear.
- Verify changes in proportion to risk and report checks that could not be run.

## Documentation synchronization

Documentation is part of the change. Update all affected current-state guides in the same commit:

- `README.md`: overview and quick start.
- `DESIGN.md`: architecture, data, security, and current behavior.
- `HANDOFF.md`: configuration, deployment, verification, and recovery.
- `CONTRIBUTING.md`: human and AI-assisted development workflow.
- `AGENTS.md`: instructions that future AI tools must follow.

Do not rewrite historical migrations. Do not update or commit `supabase/schema.sql` as documentation.

## Completion

Review the diff, confirm no secret or unrelated file is included, summarize behavior and verification, identify any required deployment, and commit or push only when the user explicitly asks.
