# CUFSC Ice Time Booking System — Design Document 4/20/2026

This document describes the full architecture of the CUFSC (Cornell University Figure Skating Club) ice time booking web app, intended for maintainers who need to understand, modify, or extend the system.

---

## 1. Overview

The system lets club members log in, view available ice sessions, and book spots. Admins manage sessions, users, bookings, and handle approval requests. Automated email alerts notify admins when new requests are submitted.

---

## 2. Technology Stack

| Layer | Technology |
|---|---|
| Frontend framework | Next.js 14 (App Router) with React |
| Language | TypeScript |
| Styling | CSS variables + utility classes in `globals.css` |
| Database + Auth + Backend | Supabase (PostgreSQL, Auth, Edge Functions, Webhooks) |
| Email | Resend API |
| Fonts | Google Fonts — Syne (headings), DM Sans (body) |
| Deployment | Vercel |

---

## 3. Platform Responsibilities

### Next.js (this repository)
Handles all UI and user interaction. Every page is a client-side React component that reads and writes data by calling Supabase RPC functions or querying views. There is no custom API layer — the frontend talks directly to Supabase.

### Supabase
Acts as the entire backend:
- **PostgreSQL database** stores all data (users, sessions, bookings, approval requests, tiers).
- **RPC functions** (PL/pgSQL) encapsulate all business logic — booking, credit deduction, cancellations, admin operations. Clients call these via `supabase.rpc()`.
- **Views** (`sessions_with_spots`, `my_bookings`) pre-compute derived data for common queries.
- **Auth** manages Google OAuth sessions. User identity is available in SQL via `auth.uid()`.
- **Row-Level Security (RLS)** controls which rows each user can read or write.
- **Database Webhooks** fire HTTP requests to Edge Functions when data changes.
- **Edge Functions** are Deno TypeScript functions deployed on Supabase infrastructure, used for tasks requiring external API calls (e.g., sending email).

### Resend
Third-party email service. The `notify-admins` Edge Function sends transactional email through Resend whenever a new approval request is created.

---

## 4. Directory Structure

```
ice-booking/
├── app/
│   ├── globals.css          # CSS variables and shared component classes
│   ├── layout.tsx           # Root layout (sets page title, imports fonts)
│   ├── page.tsx             # Entry point — redirects to /login or /dashboard
│   ├── login/page.tsx       # Google OAuth sign-in screen
│   ├── auth/callback/page.tsx  # OAuth redirect handler
│   ├── dashboard/page.tsx   # Member portal (browse sessions, book, cancel)
│   └── admin/
│       ├── layout.tsx       # Admin layout wrapper
│       ├── page.tsx         # Redirects to /admin/sessions
│       ├── sessions/page.tsx   # CRUD for ice sessions
│       ├── users/page.tsx      # CRUD for club members
│       ├── bookings/page.tsx   # Read-only view of who is in each session
│       ├── approvals/page.tsx  # Manage new-user and session booking requests
│       └── tools/page.tsx      # Admin utilities (e.g., weekly credit reset)
├── lib/
│   ├── supabaseClient.ts    # Exports a single shared Supabase client instance
│   └── ui.tsx               # Shared UI components (buttons, badges, nav, etc.)
├── supabase/
│   └── functions/
│       └── notify-admins/
│           └── index.ts     # Edge function: emails admins on new approval requests
├── .env.local               # Supabase URL and anon key (not committed to git)
└── package.json
```

---

## 5. Authentication Flow

1. User visits `/`. The page checks for an active Supabase session.
   - No session → redirect to `/login`.
   - Session exists → redirect to `/dashboard`.
2. `/login` shows a "Sign in with Google" button. Clicking it starts a Supabase OAuth flow.
3. Google redirects back to `/auth/callback`, which exchanges the OAuth code for a session and redirects to `/`.
4. All subsequent pages call `supabase.auth.getSession()` or `supabase.auth.getUser()` to get the current user's ID and email.

**Note**: Authentication checks are performed client-side on each page. Admin pages do not currently use Next.js middleware to block unauthenticated access; access control relies on Supabase RLS policies and the `is_admin` flag on the user record.

---

## 6. Data Model (Key Tables)

### `users`
Stores club member profiles. Separate from Supabase's built-in `auth.users` table.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | Matches `auth.users.id` |
| `email` | text | Cornell or other email |
| `name` | text | Display name |
| `tier` | text | e.g. `basic`, `temp`, `admin` |
| `credits_balance` | integer | Current credits available to book |
| `is_admin` | boolean | Grants access to `/admin` pages |

### `tiers`
Defines tier properties.

| Column | Notes |
|---|---|
| `name` | Tier identifier (e.g. `basic`) |
| `weekly_credits` | Credits issued each week on reset |

### `sessions`
Ice time slots.

| Column | Notes |
|---|---|
| `id` | Text ID set by admin (e.g. `SCT-2026-04-21-1800`) |
| `notes` | Optional label shown to members |
| `start_time` | timestamptz (stored in UTC) |
| `end_time` | timestamptz (stored in UTC) |
| `release_at` | timestamptz — session is not bookable before this time |
| `capacity` | Max number of bookings |

### `bookings`
Links users to sessions.

| Column | Notes |
|---|---|
| `id` | uuid |
| `user_id` | FK → `users.id` |
| `session_id` | FK → `sessions.id` |
| `status` | `active` or `cancelled` |
| `created_at` | When booking was made |

### `approval_requests`
Holds pending requests for admin review.

| Column | Notes |
|---|---|
| `id` | uuid |
| `type` | `SESSION` (member wants to book) or `NEW_USER` (someone wants to join) |
| `status` | `OPEN`, `APPROVED`, or `DENIED` |
| `user_id` | FK → `users.id` (null for NEW_USER requests) |
| `session_id` | For SESSION type requests |
| `requester_email` | Email of the person requesting (for NEW_USER) |
| `created_at` | Timestamp |

---

## 7. Key Business Logic (in Supabase RPC Functions)

All business logic lives in PostgreSQL functions. The frontend is intentionally thin — it just calls RPCs and displays results.

### Booking a session (`book_sessions`)
- Takes an array of session IDs.
- For each session, checks: user exists, session is open, enough credits, spots available.
- If user tier requires approval (e.g., `temp` tier with 0 credits), creates an `approval_requests` row instead of booking directly.
- Returns an array of `{ ok: boolean, message: string }` — one entry per session.
- On success, deducts 1 credit per session.

### Cancelling a booking (`cancel_booking`)
- Takes a booking UUID (`booking_id`).
- Marks the booking as `cancelled`.
- Refunds 1 credit if cancelled at least 30 minutes before session start.

### Credit reset (`admin_weekly_reset_credits`)
- Sets every user's `credits_balance` to their tier's `weekly_credits` value.
- Intended to run on a schedule (cron) or manually from the admin Tools page.

### Session management (`admin_upsert_session`, `admin_delete_session`)
- Upsert creates or updates a session row.
- Delete removes the session and all associated bookings.

### User management (`admin_upsert_user`, `admin_delete_user`)
- Upsert creates or updates a user profile.
- Delete removes the user and all associated data.

### Approvals
- `admin_approve_request` — approves a SESSION request and creates the booking.
- `admin_approve_user_request` — approves a NEW_USER request, creates the user profile, and optionally books a session.
- `admin_deny_request` — marks any request as DENIED.

---

## 8. Time Zone Handling

All session times are stored in UTC in the database. The database timezone is set to `America/New_York` for convenience in SQL functions, but API responses always return UTC ISO strings.

**Display**: Every `toLocaleString()` call in the frontend passes `timeZone: "America/New_York"` explicitly so session times always appear in Eastern Time regardless of where the user's browser is.

**Admin form inputs**: HTML `datetime-local` inputs produce strings with no timezone info. Two helper functions in `admin/sessions/page.tsx` handle the conversion:
- `fromET(isoString)` — converts a UTC ISO string to an ET datetime-local string for pre-filling the edit form.
- `toET(localString)` — appends the correct ET UTC offset (either `-05:00` or `-04:00` depending on DST) before sending to the database.

---

## 9. Member Dashboard

The dashboard (`/dashboard`) is the main interface for club members.

**On load**, it fetches:
- The current user's profile from `users` (name, tier, credits).
- Upcoming sessions from the `sessions_with_spots` view.
- The user's recent bookings from the `my_bookings` view (last 7 days, most future first).

**If the user has no profile** (not yet a member), the dashboard shows a "Not yet a member" screen with a "Request Access" button. Clicking it calls `request_user_access()`, which creates a `NEW_USER` approval request. If a request is already pending, the button shows a waiting message instead.

**Session statuses** (displayed as colored badges):
| Badge | Condition |
|---|---|
| Soon | `release_at` is in the future — not yet open for booking |
| Open | Bookable |
| Grace | Within 60 minutes of start — no credits deducted |
| Full | No spots left |
| Closed | Session has started with <30 min remaining |
| Ended | Session is over |

**Booking**: Members can select up to 2 sessions at a time (limited by credits). Selecting and submitting calls `book_sessions()`. For `temp` tier users needing approval, the RPC automatically creates an approval request instead of booking directly.

---

## 10. Admin Interface

All admin pages are under `/admin/` and share a top navigation bar (`AdminTopBar` from `lib/ui.tsx`).

| Page | Path | Purpose |
|---|---|---|
| Sessions | `/admin/sessions` | Create, edit, delete ice sessions |
| Users | `/admin/users` | Create, edit, delete member profiles |
| Bookings | `/admin/bookings` | View who is attending each session |
| Approvals | `/admin/approvals` | Review and approve/deny requests |
| Tools | `/admin/tools` | Run utilities (e.g., weekly credit reset) |

**Approvals** handles two request types in a single table:
- **New User** requests show the requester's email. Approving creates a user profile with default settings.
- **Session** requests show the member's name and the session they want. Approving creates the booking.

---

## 11. Email Notifications (Edge Function)

**File**: `supabase/functions/notify-admins/index.ts`

**Trigger**: A Supabase Database Webhook fires on every INSERT into `approval_requests`, calling this function via HTTP.

**What it does**:
1. Receives the new row as a JSON payload.
2. Queries `users` for all rows where `is_admin = true`.
3. Composes a plain-text email based on request type (NEW_USER or SESSION).
4. Sends the email to every admin address via the Resend API.

**Environment variables required** (set via `npx supabase secrets set`):
- `RESEND_API_KEY` — from your Resend dashboard
- `SUPABASE_URL` — automatically injected by Supabase
- `SUPABASE_SERVICE_ROLE_KEY` — automatically injected by Supabase

**Deploying changes to the function**:
```bash
export SUPABASE_ACCESS_TOKEN=<your-token>
npx supabase link --project-ref dtdyvpjmavurynbccjei
npx supabase functions deploy notify-admins
```

---

## 12. Shared UI Components (`lib/ui.tsx`)

| Component | Purpose |
|---|---|
| `LogoMark` | Red cubic SVG logo |
| `Wordmark` | "CUFSC Ice Time" brand text |
| `SpotBar` | Capacity fill bar (green → orange → red as capacity fills) |
| `Avatar` | Circle with user's first initial |
| `Loading` | Centered spinner with optional label |
| `Msg` | Inline alert (success / error / info styles) |
| `AdminTopBar` | Top nav with tabs for all admin sections |

---

## 13. Styling

Styles live in `app/globals.css`. The approach is CSS custom properties (variables) for the color palette, plus a set of reusable utility classes for common UI patterns.

**Color palette** (key variables):
| Variable | Value | Use |
|---|---|---|
| `--red` | `#B31B1B` | Cornell red, primary brand color |
| `--ink` | Dark | Primary text and backgrounds |
| `--muted` | Grey | Secondary text |
| `--border` | Light grey | Card borders, separators |
| `--success` | Green | Positive indicators |
| `--warn` | Amber | Warning indicators |

**Reusable classes**: `.card`, `.btn-primary`, `.btn-ghost`, `.btn-danger`, `.btn-link`, `.input`, `.input-sm`, `.data-table`, `.badge-{status}`, `.msg-{type}`

Most component-specific layout uses inline `style={{}}` objects in JSX.

---

## 14. Environment Variables

| Variable | Where used | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Frontend | Supabase project API endpoint |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Frontend | Public anon key for Supabase client |
| `RESEND_API_KEY` | Edge Function (Supabase secret) | Resend email API |

The `.env.local` file holds the first two. Never commit it to git. The Resend key is stored as a Supabase secret, not in the repo.

---

## 15. Known Limitations and Notes for Maintainers

- **Admin access is not middleware-protected.** The `is_admin` flag is checked client-side. RLS policies in Supabase should be the authoritative guard — verify these are correctly configured before deploying to production.
- **No optimistic updates.** After every write (book, cancel, approve, etc.), the full dataset is re-fetched from Supabase. This is simple and correct but adds a round-trip delay after each action.
- **Single message state.** Each page has one `msg` / `msgType` state. If multiple things happen in quick succession, messages overwrite each other.
- **Weekly credit reset is not automated in this repo.** The `admin_weekly_reset_credits` RPC can be triggered manually from the Tools page, or set up as a scheduled job in Supabase (Database → Scheduled Jobs / pg_cron).
- **Email notifications are plain text.** The `notify-admins` function sends simple text emails. HTML templates could be added to Resend for better formatting.
- **`from` email address in notify-admins** must be a domain verified in your Resend account. Currently set to `cornellskating@gmail.com` — update this if the sending domain changes.
