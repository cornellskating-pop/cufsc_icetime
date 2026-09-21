# CUFSC Ice Time — Technical Design

Last reconciled with the application and migrations: September 21, 2026.

## System boundary

The application is a thin Next.js client over Supabase:

```text
Next.js browser UI
  ├── Supabase Auth (Google OAuth)
  ├── RLS-protected reads and views
  └── PostgreSQL RPC functions
        ├── booking and credit transactions
        ├── admin operations
        └── approval inserts and status changes
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
All non-admin accounts were converted to the zero-credit `temp` tier by the
September 7, 2026 account-normalization migration. Admin accounts were left
unchanged. Admins can still change an individual member's tier and credits
through the checked user-management RPC.

### `tiers`

Maps a tier name to `weekly_credits`. Weekly reset matching is case-insensitive for compatibility with historical tier rows.

### `sessions`

Contains ID, start/end time, optional release time, capacity, and notes. Database constraints require ordered times, release before start, and nonnegative capacity.

From October 21 through the December 2 dress rehearsal, Fall 2026 show-practice blocks are separate zero-capacity sessions. Monday member ice is 8:00–8:35 PM and 8:35–9:10 PM, followed by Group Large practice until 9:45 PM. Wednesday member ice is 8:00–8:33 PM and 8:33–9:05 PM, followed by Group 2 and Group 1/Ice Dance practices. December 2 is reserved in full for the all-group dress rehearsal. Show-practice cards use a purple outline and tint and cannot be booked.

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
- `admin_reset_non_admin_accounts_to_temp`
- `admin_approve_request`
- `admin_approve_user_request`
- `admin_deny_request`
- `admin_weekly_reset_credits`

Approval and booking operations lock the affected rows. Approved temporary-member bookings do not charge a credit.
The non-admin account reset is a manual beginning-of-semester operation. It
atomically changes every non-admin member to the zero-credit `temp` tier while
leaving admin accounts unchanged. The Admin Tools UI requires an explicit
confirmation before invoking the checked RPC.

## Authorization

- `anon` has no table or RPC access.
- `authenticated` receives only required read grants and explicit RPC execution grants.
- Browser writes occur through RPCs rather than direct table privileges.
- Users can select only their own profile and bookings.
- Admin RPCs protect emails, credits, and detailed attendance. Members may read upcoming session attendee names through the restricted RPC below.
- Default privileges no longer automatically expose new tables or functions.

RLS remains enabled on users, sessions, bookings, approvals, tiers, and the credit audit table.

## Approval notifications

An `approval_requests` trigger calls the `notify-admins` Edge Function through `pg_net`. It runs for inserts and status updates, but the trigger function sends a webhook only for:

- Every new request insert, which produces an admin alert.
- A `NEW_USER` request changing to `APPROVED`, which produces an account confirmation.
- A `SESSION` request changing to `APPROVED`, which produces a booking confirmation.

Denials and unrelated updates do not send requester emails.

Authentication uses a random shared value:

- Database copy: Supabase Vault secret `notify_admins_webhook_secret`
- Function copy: `NOTIFY_WEBHOOK_SECRET`
- Request header: `x-webhook-secret`

The Edge Function:

1. Validates method and webhook secret.
2. Reads only the approval ID from the payload.
3. Reloads the authoritative approval record from PostgreSQL.
4. Uses the event type and authoritative request status to choose the message.
5. Loads recipient addresses.
6. Sends through Resend.

For new-request alerts, `NOTIFY_EMAIL` can override recipients with a comma-separated list; otherwise all current admin email addresses are used. Every new account-access or temporary-member session request also always notifies `cornellskating@gmail.com`. For approved accounts and sessions, the recipient is the member who submitted the request. `NOTIFY_EMAIL` does not redirect member confirmations.

`APP_URL`, `FROM_EMAIL`, and the backend key are configurable secrets. `FROM_EMAIL` controls the sender for all messages and must be a Resend-verified sender. The code fallback is `CUFSC Booking <onboarding@resend.dev>`.

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
CONTRIBUTING.md              Human and AI-assisted change workflow
AGENTS.md                    Repository instructions for AI coding tools
HANDOFF.md                   Operations and deployment
DESIGN.md                    This technical reference
.github/                     Pull-request checklist
```

Schema inspection dumps, including local `supabase/schema.sql`, are ignored. They are not maintained documentation and can include database webhook headers even when they contain no table data. Migrations are the database source of truth.

## Known operational dependencies

- The weekly reset schedule lives in Supabase’s cron schema and must be verified separately from the public-schema baseline.
- The login ID synchronization trigger lives under Auth-managed objects and is not represented by the public-schema dump.
- The sender address must be verified in Resend before changing `FROM_EMAIL`.
- Legacy Supabase API keys should be deactivated only after the frontend uses a publishable key and the Edge Function uses a secret backend key.

## Member attendance

The dashboard Attendees tab calls `list_upcoming_session_attendees()`. This fixed-search-path SECURITY DEFINER RPC requires an authenticated profile in `users`; anonymous callers and authenticated non-members cannot use it. It returns upcoming sessions (start time at or after now), including empty and unreleased sessions, sorted by start time and ID. Only active booking names are returned, ordered by signup time with booking ID as a deterministic tie-breaker. No attendee IDs, emails, tiers, or timestamps are exposed, and table RLS is unchanged.

Native accordion headers share the admin date/time, notes label, and booking-count/capacity presentation. Names flow across five columns in blocks of at most 25; unused rows are omitted and additional blocks preserve all attendees for larger sessions. Cell measurements choose full name, last-name initial, then initials, recalculating after resizing and font loading. Full names remain accessible via labels and tooltips. Attendees reload on opening the tab and after the member’s booking/cancellation refresh. The existing admin table and permissions are preserved.
