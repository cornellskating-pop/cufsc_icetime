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

Admin-tier accounts must always have administrator access (`is_admin = true`), enforced in PostgreSQL. Preserve explicit admin access on other tiers and the self-demotion guard. Treat assigning the Admin tier as granting full administrator permissions.

Attendance and infraction policy is enforced in PostgreSQL. Count active marks by entered Eastern date in Jan–Jul/Aug–Dec semesters; every third mark restricts new bookings through the next four distinct positive-capacity, non-cancelled ice dates. Keep audited undo and daily idempotency. Preserve existing bookings and credits, and enforce restrictions across member booking, approvals, and booking reactivation. Session end is the exclusive booking cutoff. Run `supabase/tests/attendance_smoke.sql` for changes in this area.

Booked but absent must never issue strikes. Require explicit admin confirmation to remove an unchecked-present active booking after the single configured delay (default 8 minutes for every session length) and before session end. Enforce eligibility, settings serialization, concurrency, batch atomicity, refunds, removal audit snapshots, and exactly-once email queuing in PostgreSQL. Never infer absence from unchecked Present boxes or schedule automatic removals. Keep the legacy absence-strike endpoint disabled. Preserve historical strikes and audited correction. Run `supabase/tests/no_show_smoke.sql`.

Read removal descriptions and cutoff timestamps from the same saved policy snapshot; never hardcode configured timing in browser copy. Admin Tools exposes only one delay, with rule-change audit and stale-save protection. Member profile RPCs may expose only the caller’s own strikes and restriction. Admin Users strike removal must use audited voiding and refresh authoritative restriction status. Read before booking must explain the saved late-removal delay, no absence strikes, strikes for unregistered skating, and the four-session-day penalty. Run `supabase/tests/penalty_controls_smoke.sql` and `tests/noShowRules.test.ts` for these controls.

Manual strike grants/removals and unregistered-skating awards require a written 3–1000-character justification, enforced by authorized PostgreSQL RPCs. Preserve original and removal explanations in `private.skating_infractions` and append ADD/REMOVE events to `private.strike_adjustments`; never delete records or fabricate legacy notes. Preserve daily uniqueness, retry idempotency, and own-member reason privacy. Keep absence-strike issuance disabled. Run `supabase/tests/strike_adjustments_smoke.sql` for these changes.

Strike reason displays use the saved award `justification`, not the `reason` category, in member profiles, Admin Users history, and Admin Bookings dated marks. Legacy missing explanations show an explicit fallback without inventing notes. `my_infractions()` exposes only the caller’s own active award explanations; correction notes, actors, audit history, and other members’ strikes stay private. Apply `20261117120000_display_recorded_strike_reasons.sql` before deploying the frontend. Run `node --test tests/strikeReason.test.ts` and the strike-adjustment SQL suite to verify recorded text, legacy fallback, and own-member privacy. This read-only change does not alter strikes, restrictions, credits, or bookings.
