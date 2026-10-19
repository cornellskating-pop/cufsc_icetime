# Adding and maintaining practices

CUFSC Ice Time • Admin guide • Updated October 15, 2026

Use a spreadsheet to prepare a batch of **new sessions**, then use **Admin → Sessions** for individual changes during the year. One row is one bookable time block or one reserved practice block—not an entire night with several groups.

## Files to start with

- [Excel template](templates/practice_sessions_template.xlsx): fill the **Import** sheet; the other sheets explain fields and show fictional examples.
- [Blank CSV template](templates/practice_sessions_template.csv): the same six column headers, ready to fill.

The examples are format demonstrations, not an approved schedule. Never import them unchanged.

## 1. Prepare the schedule

Confirm the rink times, group assignments, capacities, and booking-release dates before filling the spreadsheet. Split consecutive blocks into separate rows. For example, open member ice followed by a reserved show practice needs two rows with different IDs and times.

The template targets the existing **`public.sessions`** table:

| CSV column | Required? | What to enter | App field |
|---|---|---|---|
| `id` | Yes | A unique, permanent text ID, such as `CUFSC-2027-01-25-2000-OPEN` | Session ID |
| `start_time` | Yes | Full date/time with an explicit UTC offset | Start Time |
| `end_time` | Yes | Full date/time with an explicit UTC offset, later than start | End Time |
| `release_at` | Optional in database | Date/time when booking opens; must be earlier than start | Release At |
| `capacity` | Yes | Whole number, 0 or greater; use the approved capacity | Capacity |
| `notes` | Optional | Public session label, including any styling keywords | Label (optional) |

**The database column is `notes`, not `label`.** Do not add `label`, `spots_left`, attendee names, booking counts, credits, or `cancelled_at` to a new-session import. Remaining spots are calculated; cancellations are managed by the app. There is no separate practice-type or flair column.

IDs must not repeat within the file or match an existing session. Keep an ID unchanged when editing a session later—even if the date or time in its name becomes outdated. Changing the ID in the app can create a different session instead of renaming the original.

### Dates and Eastern Time

The app displays **America/New_York** time. CSV timestamps must identify the exact instant; use ISO 8601 text:

- During Eastern daylight time: `2026-10-21T20:00:00-04:00`
- During Eastern standard time: `2026-11-02T20:00:00-05:00`

Keep these cells as **text** so Excel does not remove the offset. Avoid entries such as `10/21/26 8:00`, `8 PM`, or `EST` without a full date and offset. PostgreSQL stores these instants as timezone-aware timestamps; the app converts them for display.

Check the offset for **each timestamp separately**, including `release_at`. A release before a daylight-saving transition and a session after it can use different offsets. Do not fill an entire fall or spring semester with a single fixed offset. Avoid the ambiguous/repeated overnight hours around the time change.

The Fall 2026 release convention in this project is Sunday at **9:00 PM Eastern**. Confirm the convention for the new semester; the import does not calculate it automatically. Weekly credit reset is a separate event, currently Sunday at **4:30 PM Eastern**.

A null `release_at` means there is no release-time gate; a future session with space may be booked immediately. For imports, explicitly filling every release timestamp is the least ambiguous approach. If you intentionally want no gate, ensure the importer treats that cell as SQL NULL, not an empty timestamp string. Alternatively omit the entire `release_at` column from a batch where every session intentionally has no gate. Never enter the literal text `NULL` unless the importer explicitly maps it to null.

### Labels and special styling

Put the label in **`notes`** in the spreadsheet or **Label** in the app. Matching is case-insensitive.

| Desired appearance | Enter this kind of label | Matching rule |
|---|---|---|
| Regular member ice | `Open member ice` | No special keyword |
| Purple show-practice block | `Show practice: Group Large` | Must start with `Show practice:` |
| General show styling | `Winter Show` | Contains `show` |
| Competition-team styling | `Competition Team Practice` | Contains `competition team`; `Comp Team` does not match |
| Tryout styling | `Team Tryouts` | Contains `tryout` |

Use one clear category per label. Avoid leading spaces before `Show practice:` and unrelated uses of the word “show.” Do not begin a normal label with `Cancelled:`; that prefix is used by the cancellation workflow.

**Styling does not restrict who can book.** A competition-team label alone does not make a session team-only. Set **capacity to 0** for reserved practice ice that should appear on the schedule but cannot be booked through the member app. Use a positive approved capacity for bookable ice. Do not set an already-booked session to zero as a substitute for cancelling it.

## 2. Export and import new sessions

1. Fill only the workbook’s **Import** sheet. Keep the exact header names, with one session per row. Do not include instruction rows, totals, merged cells, or blank rows between sessions.
2. Verify all IDs are new, all start/end times and offsets are correct, end is after start, release is before start, and capacities are whole nonnegative numbers. Check for unintended overlaps; the database does not prohibit overlapping sessions.
3. Save a dated copy of the workbook. Export **only Import** as **CSV UTF-8**. XLSX is the working template; CSV is the import file. Open the CSV in a text editor and confirm that timestamp offsets survived and labels with commas are quoted correctly.
4. Have the authorized Supabase maintainer open the correct project, then **Table Editor → public.sessions → Insert → Import Data from CSV**. Select the **existing** table; do not create a replacement table. Review the column mappings and preview before importing. This follows the [Supabase CSV import workflow](https://supabase.com/docs/guides/database/import-data).
5. Import only the approved new-session batch. Direct table imports bypass the app’s admin form checks, so the spreadsheet review matters. Do not import into `bookings`, `users`, notification tables, or calculated views.
6. If the import reports an error, check which IDs exist before retrying. Do not assume a repeated upload is an update or that no rows were inserted. Keep the CSV and an import note recording who imported it and when.

Database structure changes still belong in versioned migrations. Loading an approved schedule into the existing table is a data-entry operation; do not change table columns, policies, or permissions to make an import work.

### Check immediately afterward

Open **Admin → Sessions** and verify the imported IDs, labels, dates, release times, and capacities. Then check the member **Calendar** and **List** views: Eastern times should agree with the approved schedule, special labels should display their intended styling, and reserved practices should not be bookable. Check at least one session on each side of a daylight-saving transition. Imports become visible without a frontend deployment; a future release time prevents booking, not visibility.

## 3. Make changes during the year

For occasional edits, use [Admin → Sessions](https://cufscice.vercel.app/admin/sessions), locate the session, choose **Edit**, change the needed fields, and save. Leave its ID alone. The form uses Eastern local date/time fields; unlike the CSV, you do not type a UTC offset there.

- **Add one practice:** use **Add Session**, assign a new unique ID, and fill the same fields listed above. The form’s default capacity is 25; change it to the approved capacity or 0 for reserved ice.
- **Change a time, release, or label:** edit the existing row. Existing bookings remain attached. Ordinary edits do not send schedule-change emails, so arrange member communication separately when needed.
- **Reduce capacity:** inspect current bookings first. Do not lower capacity below the active booking count; the app’s session-edit function does not enforce that comparison.
- **Remove one member:** use **Admin → Bookings → Remove**. The removal workflow refunds a charged credit and queues an email.
- **Cancel the whole practice:** use **Cancel Session**. It cancels active bookings, refunds charged credits, closes pending requests, and queues cancellation emails. Keep the record for history; do not use Delete or a spreadsheet overwrite as the cancellation mechanism.
- **Undo cancellation:** use **Restore Session**. The popup offers reopening empty or restoring previous bookings and pending requests. This is allowed within seven days of cancellation and before the start. Full restoration reverses refunds and stops if credits have already been spent. Older cancellations may require you to confirm original capacity. Restoration itself does not email members.
- **Delete:** reserve permanent deletion for an erroneous record after checking its bookings and history. It is not the cancellation/refund/email workflow.

For a large midyear revision, ask the maintainer to review the changed IDs and make a controlled update. Do not reimport the entire original schedule or delete and recreate booked sessions. After individual edits, update the planning workbook or export a fresh schedule so an old spreadsheet does not become the next source of accidental overwrites.

## Email delivery note

“Queued” does not mean delivered. The most recent investigation in this task found cancellation email failures caused by Resend testing-sender restrictions and rate limits. A verified production sender/configuration and controlled retries still need verification before relying on cancellation emails alone. An empty reserved practice has no booked members to notify.

## Reference

Template fields and behavior were checked against the repository’s ordered migrations through `20260930120000_credit_selection_and_view_preference.sql`, the Admin Sessions form, and the dashboard styling helpers. `supabase/schema.sql` was not used. No live data is included in the template, and no sessions were imported while preparing this guide.
