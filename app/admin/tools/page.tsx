"use client";

import { useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg } from "../../../lib/ui";

export default function AdminTools() {
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success"|"error"|"info">("info");
  const [loading, setLoading] = useState<string | null>(null);

  const run = async (label: string, fn: () => Promise<any>) => {
    if (!confirm(`Run "${label}"?`)) return;
    setLoading(label);
    setMsg("");
    const { data, error } = await fn();
    setLoading(null);
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(typeof data === "string" ? data : `${label} completed.`);
    setMsgType("success");
  };

  const tools: { key: string; title: string; description: string; danger: boolean; action: () => Promise<any> }[] = [
    {
      key: "reset",
      title: "Weekly Credit Reset",
      description: "Sets every user's credits_balance to their tier's weekly_credits value. Runs automatically each week — use this to trigger manually if needed.",
      danger: false,
      action: async () => {
        const result = await supabase.rpc("admin_weekly_reset_credits");
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
                disabled={loading === t.key}
                onClick={() => run(t.title, t.action)}
                style={{ flexShrink: 0, minWidth: 120 }}
              >
                {loading === t.key ? "Running…" : "Run Now"}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}