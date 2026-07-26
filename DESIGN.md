# CUFSC Ice Time — Technical Design

Last reconciled with the application and exported Supabase schema: July 26, 2026.

## System boundary

The application is a thin Next.js client over Supabase:

```text
Next.js browser UI
  ├── Supabase Auth (Google OAuth)
  ├── RLS-protected reads and views
  └── PostgreSQL RPC functions
        ├── booking and credit transactions
        ├── admin operations
        └── approval inserts
              └── pg_net trigger
                    └── Supabase Edge Function
                          └── Resend
```

There is no custom Next.js API layer. Consequently, browser checks are usability controls; RPC authorization, RLS, constraints, and grants are authoritative.

## Technology

| Layer | Technology |
|---|---|
| Frontend | Next.js 16 App Router, React 19, TypeScript |
| Styling | Global CSS variables/classes plus component inline styles |
| Authentication | Supabase Auth with Google OAuth |
| Backend | Supabase Postgres, RLS, views, SECURITY DEFINER RPCs |
| Notification worker | Supabase Deno Edge Function |
| Email | Resend |
| Hosting | Vercel |

All displayed session times use `America/New_York`. PostgreSQL stores `timestamptz` values in UTC.

## Routes

| Route | Purpose |
|---|---|
| `/` | Redirect according to authentication state |
| `/login` | Start Google OAuth |
| `/auth/callback` | Complete the browser session |
| `/dashboard` | Member profile, sessions, bookings, and cancellations |
| `/admin/sessions` | Session management |
| `/admin/users` | Member and admin management |
| `/admin/bookings` | Attendance |
| `/admin/approvals` | New-member and booking approvals |
| `/admin/tools` | Manual credit reset |

The admin layout verifies the current profile before mounting admin pages. Every admin RPC independently checks `is_admin()` as defense in depth.

## Data model

### `users`

| Column | Meaning |
|---|---|
| `id uuid` | Normally matches `auth.users.id` |
| `email text` | Normalized lowercase login email |
| `name text` | Display name |
| `tier text` | Lowercase tier key |
| `credits_balance integer` | Spendable weekly credits |
| `is_admin boolean` | Administrative authority |
| `paid_dues boolean` | Dues status |
| `created_at timestamptz` | Creation time |

Members can read their own profile but cannot update credit, tier, dues, or admin fields directly.

### `tiers`

Maps a tier name to `weekly_credits`. Weekly reset matching is case-insensitive for compatibility with historical tier rows.

### `sessions`

Contains ID, start/end time, optional release time, capacity, and notes. Database constraints require ordered times, release before start, and nonnegative capacity.

### `bookings`

Links a user and session. Active bookings are unique per user/session. `credit_charged` records whether the booking consumed a credit, preventing free grace or approved bookings from producing a refund.

### `approval_requests`

Represents `NEW_USER` and `SESSION` requests with `OPEN`, `APPROVED`, `DENIED`, or `FAILED` status and decision metadata.

### `credit_audit`

Records booking deductions and cancellation refunds. The log intentionally retains entries with a null user reference after member deletion.

## Views

### `sessions_with_spots`

Returns sessions with active capacity remaining. It needs owner-level access to count all active bookings, but only authenticated users receive `SELECT` permission.

### `my_bookings`

Runs with the caller’s permissions and combines the current user’s bookings with session times.

Older duplicate admin views and the unused `me` view were removed. Admin data is returned only through checked RPCs.

## Booking transaction

`book_sessions(text[])` is the single booking entry point.

It:

1. Requires an authenticated member.
2. Rejects empty, duplicate, null, or more than two session IDs.
3. Locks the member row to serialize credit spending.
4. Locks each session row to serialize capacity checks.
5. Enforces `release_at`, start time, capacity, and duplicate-booking rules.
6. Creates an approval request for a zero-credit temporary member.
7. Allows a zero-credit booking in the 60-minute grace period.
8. Records whether a credit was charged.
9. Writes a credit audit entry when charging.
10. Returns one structured result per requested session.

The former `book_session` function was removed to avoid maintaining a second, divergent ruleset.

## Cancellation transaction

`cancel_booking(uuid)`:

- Requires ownership of an active booking.
- Locks the booking and user row.
- Permits cancellation until 30 minutes after session start.
- Refunds only a booking that actually charged a credit and is cancelled at least 30 minutes before start.
- Writes the refund to `credit_audit`.

## Admin transactions

All admin functions are SECURITY DEFINER, set a fixed search path, and call `is_admin()`:

- `admin_list_sessions`
- `admin_list_session_bookings_grouped`
- `admin_list_users`
- `admin_list_approvals`
- `admin_upsert_session`
- `admin_delete_session`
- `admin_upsert_user`
- `admin_delete_user`
- `admin_approve_request`
- `admin_approve_user_request`
- `admin_deny_request`
- `admin_weekly_reset_credits`

Approval and booking operations lock the affected rows. Approved temporary-member bookings do not charge a credit.

## Authorization

- `anon` has no table or RPC access.
- `authenticated` receives only required read grants and explicit RPC execution grants.
- Browser writes occur through RPCs rather than direct table privileges.
- Users can select only their own profile and bookings.
- Admin RPCs protect member names, emails, credits, and attendance.
- Default privileges no longer automatically expose new tables or functions.

RLS remains enabled on users, sessions, bookings, approvals, tiers, and the credit audit table.

## Approval notifications

An insert trigger calls the `notify-admins` Edge Function through `pg_net`.

Authentication uses a random shared value:

- Database copy: Supabase Vault secret `notify_admins_webhook_secret`
- Function copy: `NOTIFY_WEBHOOK_SECRET`
- Request header: `x-webhook-secret`

The Edge Function:

1. Validates method and webhook secret.
2. Reads only the approval ID from the payload.
3. Reloads the authoritative approval record from PostgreSQL.
4. Loads recipient addresses.
5. Sends through Resend.

`NOTIFY_EMAIL` can override recipients with a comma-separated list; otherwise all current admin email addresses are used. `APP_URL`, `FROM_EMAIL`, and the backend key are configurable secrets.

The function is deployed with platform JWT verification disabled because it performs its own webhook authentication.

## Repository structure

```text
app/                         Next.js routes and UI
lib/                         Shared Supabase client and UI components
supabase/config.toml         Local stack and Edge Function configuration
supabase/functions/          Edge Function source
supabase/migrations/         Versioned database source of truth
supabase/tests/              Transactional database smoke tests
README.md                    Developer quick start
HANDOFF.md                   Operations and deployment
DESIGN.md                    This technical reference
```

Schema inspection dumps are ignored. They can include database webhook headers even when they contain no table data.

## Known operational dependencies

- The weekly reset schedule lives in Supabase’s cron schema and must be verified separately from the public-schema baseline.
- The login ID synchronization trigger lives under Auth-managed objects and is not represented by the public-schema dump.
- The sender address must be verified in Resend before changing `FROM_EMAIL`.
- Legacy Supabase API keys should be deactivated only after the frontend uses a publishable key and the Edge Function uses a secret backend key.
