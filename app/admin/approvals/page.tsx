"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg } from "../../../lib/ui";

type Row = {
  request_id: string;
  created_at: string;
  status: string;
  user_id: string;
  user_email: string;
  user_name: string;
  session_id: string;
  session_label: string | null;
  session_start: string;
  session_end: string;
};

export default function AdminApprovals() {
  const [rows, setRows] = useState<Row[]>([]);
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success"|"error"|"info">("info");
  const [filter, setFilter] = useState<"OPEN"|"ALL">("OPEN");

  const load = async () => {
    const { data, error } = await supabase.rpc("admin_list_approvals");
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setRows((data || []) as Row[]);
  };

  useEffect(() => { load(); }, []);

  const act = async (id: string, action: "approve"|"deny") => {
    setMsg("");
    const fn = action === "approve" ? "admin_approve_request" : "admin_deny_request";
    const { data, error } = await supabase.rpc(fn, { p_request_id: id });
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(String(data)); setMsgType("success");
    load();
  };

  const fmt = (d: string) => new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York", month: "short", day: "numeric",
    hour: "numeric", minute: "2-digit",
  });

  const visible = filter === "OPEN" ? rows.filter(r => r.status === "OPEN") : rows;
  const openCount = rows.filter(r => r.status === "OPEN").length;

  return (
    <div>
      <AdminTopBar active="approvals" />
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "28px 24px 80px" }}>

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
          <div>
            <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, letterSpacing: "-0.02em" }}>
              Approvals
              {openCount > 0 && (
                <span style={{ background: "var(--red)", color: "white", fontFamily: "'Syne',sans-serif",
                  fontWeight: 700, fontSize: 12, padding: "2px 9px", borderRadius: 100, marginLeft: 10 }}>
                  {openCount}
                </span>
              )}
            </div>
            <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>
              Temp-tier members requesting session access without credits
            </div>
          </div>
          <div style={{ display: "flex", gap: 6, background: "var(--border)", borderRadius: 8, padding: 4 }}>
            {(["OPEN", "ALL"] as const).map(f => (
              <button key={f} onClick={() => setFilter(f)} style={{
                padding: "6px 14px", borderRadius: 6, border: "none", cursor: "pointer", fontSize: 12, fontWeight: 600,
                background: filter === f ? "var(--red)" : "transparent",
                color: filter === f ? "white" : "var(--muted)",
              }}>{f === "OPEN" ? `Open (${openCount})` : "All"}</button>
            ))}
          </div>
        </div>

        {msg && <Msg text={msg} type={msgType} />}

        {visible.length === 0 ? (
          <div style={{ padding: "60px 0", textAlign: "center", color: "var(--muted)" }}>
            <div style={{ fontSize: 32, marginBottom: 10 }}>✓</div>
            <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700 }}>No pending approvals</div>
          </div>
        ) : (
          <div className="card">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Requested</th>
                  <th>Member</th>
                  <th>Session</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {visible.map(r => (
                  <tr key={r.request_id}>
                    <td style={{ color: "var(--muted)", fontSize: 12, whiteSpace: "nowrap" }}>{fmt(r.created_at)}</td>
                    <td>
                      <div style={{ fontWeight: 500 }}>{r.user_name || "—"}</div>
                      <div style={{ fontSize: 11, color: "var(--muted)" }}>{r.user_email}</div>
                    </td>
                    <td>
                      <div style={{ fontWeight: 500 }}>{r.session_label || r.session_id}</div>
                      <div style={{ fontSize: 11, color: "var(--muted)" }}>{fmt(r.session_start)}</div>
                    </td>
                    <td>
                      <span className={`badge badge-${r.status === "OPEN" ? "pending" : r.status === "APPROVED" ? "approved" : "denied"}`}>
                        {r.status}
                      </span>
                    </td>
                    <td>
                      {r.status === "OPEN" ? (
                        <div style={{ display: "flex", gap: 8 }}>
                          <button className="btn-primary" style={{ padding: "6px 12px", fontSize: 11 }}
                            onClick={() => act(r.request_id, "approve")}>
                            Approve + Book
                          </button>
                          <button className="btn-danger" onClick={() => act(r.request_id, "deny")}>Deny</button>
                        </div>
                      ) : (
                        <span style={{ fontSize: 12, color: "var(--muted)" }}>—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}