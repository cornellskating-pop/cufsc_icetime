import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ApprovalRecord = {
  id: string;
  type: "NEW_USER" | "SESSION";
  requester_email: string | null;
  user_id: string | null;
  session_id: string | null;
};

type WebhookPayload = {
  record?: { id?: unknown };
};

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const BACKEND_SECRET_KEY = (() => {
  try {
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return secretKeys.default as string | undefined;
  } catch {
    return undefined;
  }
})();
const WEBHOOK_SECRET = Deno.env.get("NOTIFY_WEBHOOK_SECRET");
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") ?? "CUFSC Booking <onboarding@resend.dev>";
const APP_URL = Deno.env.get("APP_URL") ?? "https://cufscice.vercel.app";
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const validUniqueEmails = (emails: Array<string | null | undefined>) => [
  ...new Set(
    emails
      .map(email => email?.trim() ?? "")
      .filter(email => EMAIL_PATTERN.test(email)),
  ),
];

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }
    if (!WEBHOOK_SECRET || req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
      return new Response("Unauthorized", { status: 401 });
    }
    if (!RESEND_API_KEY || !SUPABASE_URL || !BACKEND_SECRET_KEY) {
      throw new Error("Required function secrets are not configured");
    }

    const payload = await req.json() as WebhookPayload;
    const approvalId = typeof payload.record?.id === "string" ? payload.record.id : null;
    if (!approvalId) {
      return new Response("Invalid webhook payload", { status: 400 });
    }

    const supabase = createClient(SUPABASE_URL, BACKEND_SECRET_KEY);

    const { data: row, error: requestError } = await supabase
      .from("approval_requests")
      .select("id, type, requester_email, user_id, session_id")
      .eq("id", approvalId)
      .single<ApprovalRecord>();
    if (requestError || !row) throw requestError ?? new Error("Approval request not found");

    const { data: admins, error: adminErr } = await supabase
      .from("users")
      .select("email")
      .eq("is_admin", true);

    if (adminErr) throw adminErr;

    const configuredRecipients = validUniqueEmails(
      (Deno.env.get("NOTIFY_EMAIL") ?? "").split(","),
    );
    const recipients = configuredRecipients.length > 0
      ? configuredRecipients
      : validUniqueEmails((admins ?? []).map(admin => admin.email));
    if (recipients.length === 0) return new Response("No notification recipients", { status: 200 });

    let subject: string;
    let body: string;

    if (row.type === "NEW_USER") {
      subject = "New member request — CUFSC Booking";
      body = `A new user has requested access to the CUFSC booking system.

Requester email: ${row.requester_email ?? "unknown"}

Review and approve or deny at: ${APP_URL}/admin/approvals`;
    } else {
      subject = "New session booking request — CUFSC Booking";

      let userEmail = "";
      const sessionId = row.session_id ?? "";

      if (row.user_id) {
        const { data: u } = await supabase
          .from("users")
          .select("email, name")
          .eq("id", row.user_id)
          .single();
        if (u) userEmail = `${u.name ?? ""} <${u.email}>`.trim();
      }

      body = `A member has requested to book a session.

Member: ${userEmail || "unknown"}
Session: ${sessionId}

Review and approve or deny at: ${APP_URL}/admin/approvals`;
    }

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: recipients,
        subject,
        text: body,
      }),
    });
    if (!res.ok) {
      throw new Error(`Resend returned ${res.status}: ${await res.text()}`);
    }

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error(err);
    return new Response(String(err), { status: 500 });
  }
});
