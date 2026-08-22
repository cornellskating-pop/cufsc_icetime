## Summary

Describe the user-visible outcome and why the change is needed.

## Verification

- [ ] `npm run lint`
- [ ] `npm run build`
- [ ] Relevant behavior tested manually
- [ ] Local Supabase reset and SQL smoke test run, or not applicable
- [ ] `supabase db push --dry-run` reviewed, or not applicable

## Security and operations

- [ ] Authentication, authorization, RLS, grants, and secret handling reviewed
- [ ] Credit, capacity, booking, cancellation, and approval behavior reviewed where relevant
- [ ] No credentials, real member data, local dumps, backups, or `.env` files included
- [ ] Deployment order, production authorization, and rollback considered

## Documentation

- [ ] `README.md` updated, or still accurate
- [ ] `DESIGN.md` updated, or still accurate
- [ ] `HANDOFF.md` updated, or still accurate
- [ ] `CONTRIBUTING.md` and `AGENTS.md` updated if the development workflow changed
- [ ] Historical migrations were not rewritten
