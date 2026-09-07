"use client";

import { useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg } from "../../../lib/ui";

type ToolResult = { data: unknown; error: { message: string } | null };
type AdminTool = {
  key: string;
  title: string;
  description: string;
  confirmation: string;
  confirmLabel: string;
  destructive?: boolean;
  action: () => PromiseLike<ToolResult>;
};

export default function AdminTools() {
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success"|"error"|"info">("info");
  const [loading, setLoading] = useState<string | null>(null);
  const [pendingTool, setPendingTool] = useState<AdminTool | null>(null);

  const run = async (label: string, fn: () => PromiseLike<ToolResult>) => {
    setLoading(label);
    setMsg("");
    const { data, error } = await fn();
    setLoading(null);
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(typeof data === "string" ? data : `${label} completed.`);
    setMsgType("success");
  };

  const tools: AdminTool[] = [
    {
      key: "reset",
      title: "Weekly Credit Reset",
      description: "Sets every user's credits_balance to their tier's weekly_credits value. Runs automatically each week — use this to trigger manually if needed.",
      confirmation: "This immediately resets credit balances using each account's current tier.",
      confirmLabel: "Reset credits",
      action: async () => {
        const result = await supabase.rpc("admin_weekly_reset_credits");
        return result;
      },
    },
    {
      key: "reset-non-admins-to-temp",
      title: "Reset non-admin accounts to temp",
      description: "Changes every non-admin account to the temp tier and resets its credit balance to zero.",
      confirmation: "This is usually run only at the beginning of a semester to reset member accounts. Every non-admin account will be changed to the temp tier and its credits will be set to zero. Admin accounts will not be changed, and prior tiers and credit balances will not be restored automatically.",
      confirmLabel: "Reset accounts",
      destructive: true,
      action: async () => {
        const result = await supabase.rpc("admin_reset_non_admin_accounts_to_temp");
        return result;
      },
    },
  ];

  return (
    <div>
      <AdminTopBar active="tools" />
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "28px 24px 80px" }}>
        <div style={{ marginBottom: 24 }}>
          <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, letterSpacing: "-0.02em" }}>Tools</div>
          <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>Administrative operations — use with care</div>
        </div>

        {msg && <Msg text={msg} type={msgType} />}

        <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: msg ? 16 : 0 }}>
          {tools.map(t => (
            <div key={t.key} className="card" style={{ padding: 20, display: "flex", alignItems: "center", justifyContent: "space-between", gap: 20 }}>
              <div>
                <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 15 }}>{t.title}</div>
                <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 4, maxWidth: 520 }}>{t.description}</div>
              </div>
              <button
                className="btn-primary"
                disabled={loading !== null}
                onClick={() => setPendingTool(t)}
                style={{ flexShrink: 0, minWidth: 120 }}
              >
                {loading === t.title ? "Running…" : "Run Now"}
              </button>
            </div>
          ))}
        </div>
      </div>

      {pendingTool && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="tool-confirmation-title"
          style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.5)", zIndex: 100,
            display: "flex", alignItems: "center", justifyContent: "center", padding: 20 }}
        >
          <div className="card" style={{ padding: 28, maxWidth: 460, width: "100%" }}>
            <div id="tool-confirmation-title" style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 18, marginBottom: 8 }}>
              Are you sure?
            </div>
            <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 10 }}>{pendingTool.title}</div>
            <div style={{ fontSize: 13, lineHeight: 1.55, color: "var(--muted)", marginBottom: 22 }}>
              {pendingTool.confirmation}
            </div>
            <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
              <button className="btn-ghost" onClick={() => setPendingTool(null)}>Cancel</button>
              <button
                className={pendingTool.destructive ? "btn-danger" : "btn-primary"}
                onClick={() => {
                  const tool = pendingTool;
                  setPendingTool(null);
                  void run(tool.title, tool.action);
                }}
              >
                {pendingTool.confirmLabel}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
