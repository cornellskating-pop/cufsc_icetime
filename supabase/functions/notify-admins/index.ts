import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FROM_EMAIL = "CUFSC Booking <cornellskating@gmail.com>";
const APP_URL = "https://ice-booking.vercel.app";

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const row = payload.record;

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: admins, error: adminErr } = await supabase
      .from("users")
      .select("email, name")
      .eq("is_admin", true);

    if (adminErr) throw adminErr;
    if (!admins || admins.length === 0) {
      return new Response("No admins found", { status: 200 });
    }

    let subject: string;
    let body: string;

    if (row.type === "NEW_USER") {
      subject = "New member request — CUFSC Booking";
      body = `A new user has requested access to the CUFSC booking system.

Requester email: ${row.requester_email ?? "unknown"}

Review and approve or deny at: ${APP_URL}/admin/approvals`;
    } else {
      subject = "New session booking request — CUFSC Booking";

      const { data: reqData } = await supabase
        .from("approval_requests")
        .select("user_id, session_id")
        .eq("id", row.id)
        .single();

      let userEmail = "";
      let sessionId = row.session_id ?? "";

      if (reqData?.user_id) {
        const { data: u } = await supabase
          .from("users")
          .select("email, name")
          .eq("id", reqData.user_id)
          .single();
        if (u) userEmail = `${u.name ?? ""} <${u.email}>`.trim();
      }

      body = `A member has requested to book a session.

Member: ${userEmail || "unknown"}
Session: ${sessionId}

Review and approve or deny at: ${APP_URL}/admin/approvals`;
    }

    const emailPromises = admins.map((admin) =>
      fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: FROM_EMAIL,
          to: admin.email,
          subject,
          text: body,
        }),
      })
    );

    await Promise.all(emailPromises);

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error(err);
    return new Response(String(err), { status: 500 });
  }
});
