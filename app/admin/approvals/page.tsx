"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg } from "../../../lib/ui";

type Row = {
  approval_id: string;
  type: string;
  created_at: string;
  status: string;
  user_id: string;
  user_email: string;
  user_name: string;
  session_id: string;
  start_time: string;
  end_time: string;
  requester_email: string | null;
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

  const actSession = async (id: string, action: "approve"|"deny") => {
    setMsg("");
    const fn = action === "approve" ? "admin_approve_request" : "admin_deny_request";
    const { data, error } = await supabase.rpc(fn, { p_request_id: id });
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(String(data)); setMsgType("success");
    load();
  };

  const actUser = async (id: string, action: "approve"|"deny") => {
    setMsg("");
    const fn = action === "approve" ? "admin_approve_user_request" : "admin_deny_request";
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
              Session requests and new member requests
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
                  <th>Type</th>
                  <th>Details</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {visible.map(r => (
                  <tr key={r.approval_id}>
                    <td style={{ color: "var(--muted)", fontSize: 12, whiteSpace: "nowrap" }}>{fmt(r.created_at)}</td>
                    <td>
                      <span style={{
                        background: r.type === "NEW_USER" ? "var(--red)" : "var(--ink)",
                        color: "white", fontFamily: "'Syne',sans-serif",
                        fontSize: 9, fontWeight: 700, padding: "2px 8px", borderRadius: 100,
                        textTransform: "uppercase", letterSpacing: "0.05em", whiteSpace: "nowrap",
                      }}>
                        {r.type === "NEW_USER" ? "New User" : "Session"}
                      </span>
                    </td>
                    <td>
                      {r.type === "NEW_USER" ? (
                        <div style={{ fontSize: 13, color: "var(--muted)" }}>{r.requester_email}</div>
                      ) : (
                        <>
                          <div style={{ fontWeight: 500 }}>{r.user_name || "—"}</div>
                          <div style={{ fontSize: 11, color: "var(--muted)" }}>{r.user_email}</div>
                          <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 2 }}>
                            {r.session_id}{r.start_time ? ` · ${fmt(r.start_time)}` : ""}
                          </div>
                        </>
                      )}
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
                            onClick={() => r.type === "NEW_USER" ? actUser(r.approval_id, "approve") : actSession(r.approval_id, "approve")}>
                            {r.type === "NEW_USER" ? "Approve + Add" : "Approve + Book"}
                          </button>
                          <button className="btn-danger"
                            onClick={() => r.type === "NEW_USER" ? actUser(r.approval_id, "deny") : actSession(r.approval_id, "deny")}>
                            Deny
                          </button>
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
