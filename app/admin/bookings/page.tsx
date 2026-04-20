"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg } from "../../../lib/ui";

type BookingEntry = {
  booking_id: string;
  created_at: string;
  user_id: string;
  email: string;
  name: string;
  tier: string;
  status: string;
};

type SessionGroup = {
  session_id: string;
  start_time: string;
  end_time: string;
  label: string | null;
  capacity: number;
  bookings: BookingEntry[];
};

export default function AdminBookings() {
  const [groups, setGroups] = useState<SessionGroup[]>([]);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success" | "error" | "info">("info");

  const load = async () => {
    const [{ data: sessionData, error: sErr }, { data: bookingData, error: bErr }] = await Promise.all([
      supabase.rpc("admin_list_sessions"),
      supabase.rpc("admin_list_session_bookings_grouped"),
    ]);
    if (sErr) { setMsg(sErr.message); setMsgType("error"); return; }
    if (bErr) { setMsg(bErr.message); setMsgType("error"); return; }

    const bookingMap = new Map<string, BookingEntry[]>();
    ((bookingData || []) as any[]).forEach(row => {
      bookingMap.set(row.session_id, ((row.bookings || []) as BookingEntry[]).filter(b => b.status === "active"));
    });

    const now = new Date();
    const endOfWeek = new Date(now);
    const daysUntilSunday = now.getDay() === 0 ? 0 : 7 - now.getDay();
    endOfWeek.setDate(now.getDate() + daysUntilSunday);
    endOfWeek.setHours(23, 59, 59, 999);

    const allSessions = (sessionData || []) as any[];

    const past8 = allSessions
      .filter(s => new Date(s.end_time) < now)
      .slice(-8)
      .reverse();

    const thisWeek = allSessions
      .filter(s => new Date(s.start_time) >= now && new Date(s.start_time) <= endOfWeek);

    const combined: SessionGroup[] = [...thisWeek, ...past8].map(s => ({
      session_id: s.id,
      start_time: s.start_time,
      end_time: s.end_time,
      label: s.notes ?? null,
      capacity: s.capacity,
      bookings: bookingMap.get(s.id) || [],
    }));

    setGroups(combined);
    setExpanded(new Set(thisWeek.map((s: any) => s.id)));
  };

  useEffect(() => { load(); }, []);

  const toggle = (id: string) =>
    setExpanded(prev => { const s = new Set(prev); s.has(id) ? s.delete(id) : s.add(id); return s; });

  const fmt = (d: string) => new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York", weekday: "short", month: "short",
    day: "numeric", hour: "numeric", minute: "2-digit",
  });

  const fmtShort = (d: string) => new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York", month: "short", day: "numeric",
    hour: "numeric", minute: "2-digit",
  });

  const now = new Date();
  const totalActive = groups.reduce((s, g) => s + g.bookings.length, 0);

  return (
    <div>
      <AdminTopBar active="bookings" />
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "28px 24px 80px" }}>
        <div style={{ marginBottom: 20 }}>
          <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, letterSpacing: "-0.02em" }}>Bookings</div>
          <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>
            {groups.length} sessions · {totalActive} active bookings
          </div>
        </div>

        {msg && <Msg text={msg} type={msgType} />}

        {groups.length === 0 ? (
          <div style={{ padding: "40px 0", textAlign: "center", color: "var(--muted)" }}>No sessions to show.</div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            {groups.map(g => {
              const isPast = new Date(g.end_time) < now;
              const isOpen = expanded.has(g.session_id);
              return (
                <div key={g.session_id} className="card">
                  <div
                    onClick={() => toggle(g.session_id)}
                    style={{
                      padding: "14px 20px", cursor: "pointer",
                      background: isPast ? "var(--muted-bg, #f5f5f5)" : "var(--ink)",
                      display: "flex", alignItems: "center", justifyContent: "space-between",
                    }}
                  >
                    <div>
                      <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14, color: isPast ? "var(--ink)" : "white" }}>
                        {fmt(g.start_time)}
                        <span style={{ color: isPast ? "var(--muted)" : "#888", fontWeight: 400 }}>
                          {" – "}{new Date(g.end_time).toLocaleString("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" })}
                        </span>
                      </div>
                      {g.label && <div style={{ fontSize: 11, color: isPast ? "var(--muted)" : "#888", marginTop: 2 }}>{g.label}</div>}
                    </div>
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <span style={{
                        background: g.bookings.length > 0 ? "var(--red)" : "var(--border)",
                        color: g.bookings.length > 0 ? "white" : "var(--muted)",
                        fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 12,
                        padding: "3px 10px", borderRadius: 100,
                      }}>
                        {g.bookings.length} / {g.capacity}
                      </span>
                      <span style={{ color: isPast ? "var(--muted)" : "#666", fontSize: 12 }}>{isOpen ? "▲" : "▼"}</span>
                    </div>
                  </div>

                  {isOpen && (
                    g.bookings.length === 0 ? (
                      <div style={{ padding: "16px 20px", fontSize: 13, color: "var(--muted)" }}>No bookings for this session.</div>
                    ) : (
                      <table className="data-table">
                        <thead>
                          <tr>
                            <th>#</th>
                            <th>Name</th>
                            <th>Email</th>
                            <th>Tier</th>
                            <th>Signed Up</th>
                          </tr>
                        </thead>
                        <tbody>
                          {g.bookings.map((b, i) => (
                            <tr key={b.booking_id}>
                              <td style={{ color: "var(--muted)", fontSize: 12 }}>{i + 1}</td>
                              <td style={{ fontWeight: 500 }}>{b.name || "—"}</td>
                              <td style={{ color: "var(--muted)", fontSize: 12 }}>{b.email}</td>
                              <td>
                                <span style={{
                                  background: "var(--ink)", color: "white", fontFamily: "'Syne',sans-serif",
                                  fontSize: 9, fontWeight: 700, padding: "2px 7px", borderRadius: 100,
                                  textTransform: "uppercase", letterSpacing: "0.04em",
                                }}>
                                  {b.tier}
                                </span>
                              </td>
                              <td style={{ color: "var(--muted)", fontSize: 12 }}>{fmtShort(b.created_at)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
