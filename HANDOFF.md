# CUFSC Ice Time Booking — Handoff Guide

This guide is for someone taking over maintenance of the booking system. It assumes you have login credentials for all services and basic coding familiarity, but may be new to this specific workflow.

---

## What You Have Access To

| Service | What it is | URL |
|---|---|---|
| GitHub | Stores the code | github.com |
| Vercel | Hosts the live website | vercel.com |
| Supabase | Database and backend | supabase.com |
| Resend | Sends admin email notifications | resend.com |

---

## Setting Up Your Computer

You only need to do this once.

**1. Install Node.js**
Download and install from nodejs.org. This is required to run the project locally.

**2. Install Git**
Download from git-scm.com. This is how you send code changes to GitHub.

**3. Install VS Code**
Download from code.visualstudio.com. This is the code editor.

**4. Clone the repository**
Open a terminal and run:
```bash
git clone <your-github-repo-url>
cd ice-booking
npm install
```
`npm install` downloads all the project's dependencies. Run it once after cloning.

**5. Create the environment file**
Create a file called `.env.local` in the root of the project folder with:
```
NEXT_PUBLIC_SUPABASE_URL=https://dtdyvpjmavurynbccjei.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<get this from Supabase dashboard → Settings → API>
```
This file connects your local copy to the Supabase database. Never commit this file to GitHub.

**6. Enable local login (one-time Supabase setting)**
The live site uses `https://cufscice.vercel.app` for Google login redirects. To make login work locally too, you need to add localhost as an allowed redirect URL:
1. Go to supabase.com → your project → **Authentication → URL Configuration**
2. Under **Redirect URLs**, click **Add URL**
3. Add `http://localhost:3000/auth/callback`

Without this step, clicking "Sign in with Google" on localhost will redirect back to the live site after login instead of your local copy.

**7. Run the app locally**
```bash
npm run dev
```
Open your browser to `http://localhost:3000`. You're now running a local copy of the site. Changes you make to code will appear here instantly.

---

## How to Make and Deploy a Change

This is the workflow you'll use every time you want to update the site.

**1. Make your code change** in VS Code and save the file.

**2. Test it locally** by checking `http://localhost:3000` in your browser.

**3. To make update to live site: Open a terminal in the project folder and run:**
```bash
git add .
git commit -m "Brief description of what you changed"
git push
```

**4. Vercel automatically detects the push** and deploys the new version to the live site within about a minute. You can watch the progress at vercel.com.

That's the full cycle — edit, test locally, push to GitHub, Vercel deploys.

---

## Common Admin Tasks (No Coding Required)

These are done directly in the browser at the live site or in Supabase — no code changes needed.

**Add a new member**
Go to `/admin/users` → click "+ Add User" → fill in their details.

**Add a new ice session**
Go to `/admin/sessions` → click "+ Add Session" → fill in the date, time, and capacity.

**Approve a booking or new member request**
Go to `/admin/approvals` → click "Approve + Book" or "Approve + Add".

**Reset weekly credits manually**
Go to `/admin/tools` → click "Run Now" on the Weekly Credit Reset tool.
(This also runs automatically every Sunday at 4:30pm.)

**View who is attending a session**
Go to `/admin/bookings` → click on any session to expand the attendee list.

---

## Project Structure (What's in Each Folder)

```
ice-booking/
├── app/                  ← All the pages of the website
│   ├── dashboard/        ← What members see when they log in
│   └── admin/            ← Admin interface (sessions, users, bookings, approvals, tools)
├── lib/
│   ├── supabaseClient.ts ← Database connection (don't touch)
│   └── ui.tsx            ← Shared visual components (buttons, nav bar, etc.)
├── supabase/
│   └── functions/
│       └── notify-admins/
│           └── index.ts  ← Email notification function (runs on Supabase, not locally)
├── .env.local            ← Secret keys — never commit to GitHub
└── DESIGN.md             ← Full technical design document
```

---

## Making Changes to the Database

The database lives entirely in Supabase. To change how data is stored or how business logic works (e.g. how credits are deducted), you edit SQL functions in the Supabase dashboard:

1. Go to supabase.com → your project
2. Go to **Database → Functions** to view and edit the RPC functions
3. Go to **SQL Editor** to run one-off queries or test changes

Be careful here — changes to the database affect the live site immediately and can't be automatically undone.

---

## Updating the Email Notification Function

The `notify-admins` function runs on Supabase, not on Vercel, so pushing to GitHub does **not** update it. You have to deploy it separately.

**One-time setup:**
1. Install the Supabase CLI: `npm install -g supabase`
2. Get a Supabase access token from supabase.com → Account → Access Tokens
3. Run: `export SUPABASE_ACCESS_TOKEN=<your-token>`
4. Run: `npx supabase link --project-ref dtdyvpjmavurynbccjei`

**Every time you change the function:**
```bash
npx supabase functions deploy notify-admins
```

---

## If Something Breaks

**The live site is down or showing errors:**
- Check vercel.com → your project → Deployments to see if the last deployment failed
- Check the deployment logs for error messages

**A database operation is failing:**
- Go to Supabase → **Edge Functions → notify-admins → Logs** (for email issues)
- Go to Supabase → **Database → Logs** (for query errors)

**Email notifications stopped working:**
- Check Resend dashboard → Logs to see if emails are being attempted
- Check Supabase → Edge Functions → notify-admins → Logs for errors

**Something looks wrong with the data:**
- Go to Supabase → **Table Editor** to view and manually edit rows
- Use the **SQL Editor** to run queries if needed

---

## Things to Know

- **You never need to touch Vercel directly** for normal updates — just push to GitHub.
- **`.env.local` is never committed to GitHub** — if you set up on a new computer you'll need to recreate it with the keys from Supabase.
- **The database timezone is set to America/New_York.** All session times are stored in UTC and displayed in Eastern Time.
- **Weekly credits reset automatically** every Sunday at 4:30pm ET via a scheduled database job. You can also trigger it manually from `/admin/tools`.
- **The full technical reference** is in `DESIGN.md` if you need to understand how any part of the system works in depth.
