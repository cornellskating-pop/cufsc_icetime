"use client";
import React from "react";

export function LogoMark({ size = 32 }: { size?: number }) {
  return (
    <div style={{ width: size, height: size, background: "var(--red)", borderRadius: size * 0.2,
      display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
      <svg width={size * 0.55} height={size * 0.55} viewBox="0 0 24 24" fill="none"
        stroke="white" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2L2 7l10 5 10-5-10-5z"/>
        <path d="M2 17l10 5 10-5"/>
        <path d="M2 12l10 5 10-5"/>
      </svg>
    </div>
  );
}

export function Wordmark({ size = 15 }: { size?: number }) {
  return (
    <span style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: size, letterSpacing: "-0.02em" }}>
      CUFSC <span style={{ color: "var(--red)" }}>Ice Time</span>
    </span>
  );
}

export function SpotBar({ used, cap }: { used: number; cap: number }) {
  const pct = cap > 0 ? Math.min(100, Math.round((used / cap) * 100)) : 0;
  const color = pct >= 90 ? "var(--red)" : pct >= 65 ? "#E8923C" : "var(--success)";
  return (
    <div style={{ height: 3, background: "var(--border)", borderRadius: 100, marginTop: 5, overflow: "hidden" }}>
      <div style={{ width: `${pct}%`, height: "100%", background: color, borderRadius: 100 }} />
    </div>
  );
}

export function Avatar({ name, size = 32 }: { name: string; size?: number }) {
  return (
    <div style={{ width: size, height: size, borderRadius: "50%", background: "var(--red)",
      color: "white", fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: size * 0.42,
      display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
      {(name || "?")[0].toUpperCase()}
    </div>
  );
}

export function Loading({ label = "Loading…" }: { label?: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center",
      minHeight: "60vh", flexDirection: "column", gap: 12, color: "var(--muted)", fontSize: 14 }}>
      <div style={{ width: 28, height: 28, border: "2.5px solid var(--border)",
        borderTopColor: "var(--red)", borderRadius: "50%", animation: "spin .7s linear infinite" }} />
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      {label}
    </div>
  );
}

export function Msg({ text, type = "info" }: { text: string; type?: "success"|"error"|"info" }) {
  if (!text) return null;
  return <div className={`msg msg-${type}`}>{text}</div>;
}

export function AdminTopBar({ active }: { active: string }) {
  const tabs = [
    { key: "sessions",  href: "/admin/sessions",  label: "Sessions" },
    { key: "users",     href: "/admin/users",      label: "Users" },
    { key: "bookings",  href: "/admin/bookings",   label: "Bookings" },
    { key: "approvals", href: "/admin/approvals",  label: "Approvals" },
    { key: "tools",     href: "/admin/tools",      label: "Tools" },
  ];
  return (
    <div style={{ background: "var(--ink)", padding: "14px 24px",
      display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 12 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <LogoMark size={26} />
        <span style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 13, color: "white" }}>
          Admin Console
        </span>
        <a href="/dashboard" style={{ fontSize: 11, color: "#666", marginLeft: 8, textDecoration: "none" }}>
          ← Member view
        </a>
      </div>
      <div style={{ display: "flex", gap: 3, background: "rgba(255,255,255,0.07)", borderRadius: 10, padding: 4 }}>
        {tabs.map(t => (
          <a key={t.key} href={t.href} style={{ fontSize: 11, fontWeight: 600, padding: "6px 12px", borderRadius: 7,
            textDecoration: "none",
            background: active === t.key ? "var(--red)" : "transparent",
            color: active === t.key ? "white" : "#999", transition: "all .15s" }}>
            {t.label}
          </a>
        ))}
      </div>
    </div>
  );
}